import Foundation

/// Embedded Metal shader source for the "Pro" renderer. Compiled at
/// runtime via `device.makeLibrary(source:options:)` so we don't have
/// to depend on SwiftPM's `.metal` → `default.metallib` resource
/// pipeline (which was silently producing no metallib on this target,
/// causing the renderer to fail to init and the MTKView to show the
/// window background → all-white screen).
///
/// One-time compile cost on first toggle; cached for the process
/// lifetime by `GraphRenderer`.
enum GraphShaderSource {
    static let metal: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4x4 worldToClip;
        // Viewport size in POINTS (not pixels). Used by the drift
        // wobble to translate node positions in screen-space, so the
        // wobble amplitude stays constant regardless of camera zoom
        // (matching the Canvas path's screen-pixel drift behavior).
        float2 viewportSize;
        float time;
        // Camera zoom factor — needed in-shader for the soft
        // zoom-coupled node radius (`sqrt(scale)` clamp) the Canvas
        // path applies in `radiusFor(nodeID:)`.
        float scale;
        // Camera pan in points. The worldToClip matrix bakes the
        // FULL pan in; per-vertex parallax then subtracts a
        // depth-dependent share so deep nodes track the pan at 55%
        // (matching the Canvas path's `parallax(d)`).
        float2 cameraTranslate;
        float2 _pad;
    };

    // Per-node drift wobble. Returns a screen-space offset (in
    // points) derived from a per-node 0..1 seed and the wall-clock
    // time. Mirrors `GraphCanvasView.driftFor(_:)` — two harmonic
    // sums per axis, each with its own phase + frequency.
    inline float2 nodeDrift(float seed, float t) {
        float pa = seed * 6.28318;
        float pb = fract(seed * 7.91) * 6.28318;
        float pc = fract(seed * 13.37) * 6.28318;
        float pd = fract(seed * 23.71) * 6.28318;
        float fa = 1.0 + fract(seed * 3.14) * 1.5;
        float fb = 1.4 + fract(seed * 5.93) * 1.5;
        float fc = 1.0 + fract(seed * 11.29) * 1.5;
        float fd = 1.4 + fract(seed * 19.47) * 1.5;
        // Sea-anemone amplitudes — slow swaying, not leaves-in-storm.
        // Amplitudes ~5/3 pt, frequencies halved (× 0.5) so each
        // oscillation takes ~2× longer. Keep in sync with
        // `GraphDrift.offset(seed:time:)`.
        float tt = t * 0.5;
        float wx = sin(tt * fa + pa) * 5.0 + sin(tt * fb + pb) * 3.0;
        float wy = cos(tt * fc + pc) * 5.0 + cos(tt * fd + pd) * 3.0;
        return float2(wx, wy);
    }

    // Depth-aware parallax. The projection matrix applies the full
    // camera pan; this returns the screen-point correction that
    // pulls a node at `depth` (0 = deep past, 1 = present) back to
    // a `0.55 + 0.45 * depth` pan rate. Mirrors
    // `GraphCanvasView.parallax(_:)` and
    // `GraphProjection.screenPoint(world:depth:)`.
    inline float2 parallaxCorrection(float depth, constant Uniforms& u) {
        float pf = 0.55 + 0.45 * depth;
        return -(1.0 - pf) * u.cameraTranslate;
    }

    // Soft zoom coupling for node radii — mirrors the Canvas path's
    // `radiusFor(nodeID:)`: screen radius = world radius ×
    // clamp(sqrt(scale), 0.55, 1.9), NOT × scale. Returns the
    // world-space radius that projects to that screen radius.
    inline float zoomCoupledWorldRadius(float worldRadius, float scale) {
        float zf = clamp(sqrt(scale), 0.55, 1.9);
        return worldRadius * zf / max(scale, 0.0001);
    }

    // Translate a clip position by a screen-point offset.
    inline float4 offsetClip(float4 clip, float2 pts, constant Uniforms& u) {
        clip.xy += float2(pts.x * 2.0 / u.viewportSize.x,
                          -pts.y * 2.0 / u.viewportSize.y);
        return clip;
    }

    // -------- Edges --------

    // Edges are tessellated CPU-side into short straight segments
    // along a quadratic Bézier (see GraphRenderer.uploadEdges), so
    // every vertex carries BOTH endpoint seeds + depths plus its
    // curve parameter `t`. The drift wobble and parallax are then
    // blended along the curve — at t=0/1 a vertex exactly tracks its
    // node, and interior points interpolate — so a curved edge stays
    // glued to both wobbling nodes.
    struct EdgeVertexIn {
        float2 position  [[attribute(0)]];
        float4 color     [[attribute(1)]];
        float2 seeds     [[attribute(2)]];   // seed0, seed1
        float4 params    [[attribute(3)]];   // depth0, depth1, t, pad
    };

    struct EdgeVertexOut {
        float4 position [[position]];
        float4 color;
    };

    vertex EdgeVertexOut edge_vertex(EdgeVertexIn in [[stage_in]],
                                     constant Uniforms& u [[buffer(1)]]) {
        EdgeVertexOut out;
        float4 clip = u.worldToClip * float4(in.position, 0.0, 1.0);
        float t = in.params.z;
        float2 drift = mix(nodeDrift(in.seeds.x, u.time),
                           nodeDrift(in.seeds.y, u.time), t);
        float2 par = mix(parallaxCorrection(in.params.x, u),
                         parallaxCorrection(in.params.y, u), t);
        out.position = offsetClip(clip, drift + par, u);
        out.color = in.color;
        return out;
    }

    fragment float4 edge_fragment(EdgeVertexOut in [[stage_in]]) {
        return in.color;
    }

    // -------- Nodes (instanced discs) --------

    struct NodeVertexIn {
        float2 corner [[attribute(0)]];
    };

    struct NodeInstance {
        float2 center;
        // .x = world-space radius (depth size cue pre-baked).
        // .y = 0..1 hash seed for the drift wobble.
        float2 radius;
        // Premultiplied display color: depth desaturation + depth
        // opacity + highlight dimming all baked in CPU-side at
        // extraction (they only change on graph / selection / hops
        // changes, never per frame).
        float4 color;
        // .x = era depth (0 deep past … 1 present) — drives parallax
        //      and the foreground drop shadow.
        // .y = light-fill flag (1 = paint the lit-from-upper-left
        //      radial highlight; 0 for dimmed background nodes).
        // .z/.w unused.
        float4 params;
    };

    struct NodeVertexOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
        float  lightFill;
        // Inner edge of the shadow falloff in uv units (shadow pass
        // only; unused by the main disc pass).
        float  shadowInner;
    };

    vertex NodeVertexOut node_vertex(NodeVertexIn in [[stage_in]],
                                      uint iid [[instance_id]],
                                      constant NodeInstance* instances [[buffer(2)]],
                                      constant Uniforms& u [[buffer(1)]]) {
        NodeInstance inst = instances[iid];
        NodeVertexOut out;
        float worldR = zoomCoupledWorldRadius(inst.radius.x, u.scale);
        float2 worldPos = inst.center + in.corner * worldR;
        float4 clip = u.worldToClip * float4(worldPos, 0.0, 1.0);
        // Screen-space drift wobble + depth parallax — both applied
        // post-projection in NDC so amplitude stays constant on
        // screen regardless of zoom.
        float2 offset = nodeDrift(inst.radius.y, u.time)
                      + parallaxCorrection(inst.params.x, u);
        out.position = offsetClip(clip, offset, u);
        out.uv = in.corner;
        out.color = inst.color;
        out.lightFill = inst.params.y;
        out.shadowInner = 0.0;
        return out;
    }

    fragment float4 node_fragment(NodeVertexOut in [[stage_in]]) {
        float r = length(in.uv);
        float w = fwidth(r);
        float alpha = 1.0 - smoothstep(1.0 - w, 1.0, r);
        if (alpha <= 0.0) discard_fragment();
        float4 c = in.color;
        // Lit-from-upper-left radial highlight — mirrors the Canvas
        // path's `applyNodeHighlight`: bright spot inset toward the
        // top-left, stops 0.55 @ 0 → 0.18 @ 0.35 → 0 @ 0.85 of an
        // end radius of 0.7 × disc width (uv 1.4). Foreground
        // (in-highlight) fills only; dimmed nodes stay flat.
        if (in.lightFill > 0.5) {
            float d = distance(in.uv, float2(-0.44, -0.44)) / 1.4;
            float h = d < 0.35
                ? mix(0.55, 0.18, d / 0.35)
                : mix(0.18, 0.0, clamp((d - 0.35) / 0.5, 0.0, 1.0));
            c.rgb = mix(c.rgb, float3(1.0), h * c.a);
        }
        c.a *= alpha;
        return c;
    }

    // -------- Node depth shadows --------
    //
    // The Canvas path gives foreground nodes (depth > 0.5) a drop
    // shadow that sharpens + darkens toward the present:
    //   radius 8 → 2, alpha 0.18 → 0.50, dy 1 → 3.5.
    // Here that's a second instanced pass over the same buffer,
    // drawn under the discs: a feathered dark disc offset downward.

    vertex NodeVertexOut node_shadow_vertex(NodeVertexIn in [[stage_in]],
                                            uint iid [[instance_id]],
                                            constant NodeInstance* instances [[buffer(2)]],
                                            constant Uniforms& u [[buffer(1)]]) {
        NodeInstance inst = instances[iid];
        NodeVertexOut out;
        float depth = inst.params.x;
        float t = clamp((depth - 0.5) / 0.5, 0.0, 1.0);
        float shadowBlur  = 8.0 - 6.0 * t;      // points
        float shadowAlpha = (0.18 + 0.32 * t)
            * step(0.5, depth)                  // back half: no shadow
            * inst.color.a;                     // dimmed nodes cast faint shadows
        float shadowDy    = 1.0 + 2.5 * t;      // points, downward

        float zf = clamp(sqrt(u.scale), 0.55, 1.9);
        float screenR = inst.radius.x * zf;     // disc radius in points
        float quadR = screenR + shadowBlur;     // quad covers the feather
        float worldQuadR = quadR / max(u.scale, 0.0001);

        float2 worldPos = inst.center + in.corner * worldQuadR;
        float4 clip = u.worldToClip * float4(worldPos, 0.0, 1.0);
        float2 offset = nodeDrift(inst.radius.y, u.time)
                      + parallaxCorrection(depth, u)
                      + float2(0.0, shadowDy);
        out.position = offsetClip(clip, offset, u);
        out.uv = in.corner;
        out.color = float4(0.0, 0.0, 0.0, shadowAlpha);
        out.lightFill = 0.0;
        // Feather band runs from (screenR - blur) to the quad edge.
        out.shadowInner = max(screenR - shadowBlur, 0.0) / quadR;
        return out;
    }

    fragment float4 node_shadow_fragment(NodeVertexOut in [[stage_in]]) {
        float r = length(in.uv);
        float a = (1.0 - smoothstep(in.shadowInner, 1.0, r)) * in.color.a;
        if (a <= 0.003) discard_fragment();
        return float4(0.0, 0.0, 0.0, a);
    }

    // -------- Atmosphere specks --------
    //
    // Sparse deep-background star-field. World-positioned (so they
    // scale with zoom and reveal under pan) but with fixed
    // screen-point radii and the deepest parallax (depth 0), matching
    // the Canvas path's `atmosphereSpecks`. Twinkle is computed
    // per-fragment from the per-speck phase.

    struct SpeckInstance {
        float2 center;   // world
        float radius;    // screen points (0.6 – 1.6)
        float phase;     // twinkle phase
    };

    struct SpeckVertexOut {
        float4 position [[position]];
        float2 uv;
        float alpha;
        float inner;     // disc edge in uv units (feather outside)
    };

    vertex SpeckVertexOut speck_vertex(NodeVertexIn in [[stage_in]],
                                       uint iid [[instance_id]],
                                       constant SpeckInstance* instances [[buffer(2)]],
                                       constant Uniforms& u [[buffer(1)]]) {
        SpeckInstance inst = instances[iid];
        SpeckVertexOut out;
        float feather = 0.75;
        float quadR = inst.radius + feather;            // points
        float worldQuadR = quadR / max(u.scale, 0.0001);
        float2 worldPos = inst.center + in.corner * worldQuadR;
        float4 clip = u.worldToClip * float4(worldPos, 0.0, 1.0);
        out.position = offsetClip(clip, parallaxCorrection(0.0, u), u);
        out.uv = in.corner;
        float twinkle = 0.45 + 0.4 * sin(u.time * 0.6 + inst.phase);
        out.alpha = twinkle * 0.45;
        out.inner = inst.radius / quadR;
        return out;
    }

    fragment float4 speck_fragment(SpeckVertexOut in [[stage_in]]) {
        float r = length(in.uv);
        float a = (1.0 - smoothstep(in.inner, 1.0, r)) * in.alpha;
        if (a <= 0.003) discard_fragment();
        return float4(1.0, 1.0, 1.0, a);
    }
    """
}
