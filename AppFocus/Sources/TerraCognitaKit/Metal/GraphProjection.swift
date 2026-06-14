import Foundation
import CoreGraphics

/// Shared screen-space math for the Metal "Pro" renderer and its
/// SwiftUI overlays. The GPU shader, the hit-testing code, and every
/// overlay (labels, halo, hover ring, puff, hero images, bridge
/// rings) must agree on three things for the composite to read as
/// one surface:
///
///   1. the world → screen projection (including the depth-aware
///      parallax pan the Canvas path established),
///   2. the soft zoom-coupled node radius (`sqrt(scale)` clamp), and
///   3. the per-node depth size multiplier.
///
/// Keep the formulas here in lockstep with `GraphShaderSource`'s
/// `parallaxCorrection` / `zoomCoupledWorldRadius`.
struct GraphProjection {
    var camera: GraphRenderer.Camera
    var viewSize: CGSize

    /// Parallax factor for a node at era depth `d` (0 = deep past,
    /// 1 = present). Foreground tracks the pan 1:1, the deepest
    /// layer at ~55% — mirrors `GraphCanvasView.parallax(_:)`.
    static func parallaxFactor(depth: Double) -> CGFloat {
        CGFloat(0.55 + 0.45 * depth)
    }

    /// Depth size cue — older-era nodes shrink slightly. Mirrors
    /// the Canvas path's `depthSizeMul`.
    static func depthSizeMultiplier(depth: Double) -> CGFloat {
        0.85 + 0.35 * CGFloat(depth)
    }

    /// Soft zoom coupling for node radii: screen radius = world
    /// radius × clamp(sqrt(scale), 0.55, 1.9). Keeps small details
    /// legible zoomed out and stops hubs dominating zoomed in.
    var zoomFactor: CGFloat {
        min(1.9, max(0.55, sqrt(camera.scale)))
    }

    /// Project a world point to screen, applying the depth parallax.
    /// Does NOT include the per-frame drift wobble — callers that
    /// need to sit on the wobbling disc add
    /// `GraphDrift.offset(seed:time:)` themselves.
    func screenPoint(world: CGPoint, depth: Double) -> CGPoint {
        let pf = Self.parallaxFactor(depth: depth)
        return CGPoint(
            x: viewSize.width / 2 + world.x * camera.scale + camera.tx * pf,
            y: viewSize.height / 2 + world.y * camera.scale + camera.ty * pf)
    }

    /// Inverse projection at foreground parallax (pf = 1) — same
    /// convention as the Canvas path's `worldPoint(at:size:)`: taps
    /// and spawn points live on the foreground plane.
    func worldPoint(screen: CGPoint) -> CGPoint {
        CGPoint(
            x: (screen.x - viewSize.width / 2 - camera.tx) / camera.scale,
            y: (screen.y - viewSize.height / 2 - camera.ty) / camera.scale)
    }

    /// On-screen radius for a node disc: world radius × depth size
    /// cue × zoom coupling. Matches what the GPU draws, so hit
    /// areas and overlay rings land where the eye expects.
    func screenRadius(worldRadius: CGFloat, depth: Double) -> CGFloat {
        worldRadius * Self.depthSizeMultiplier(depth: depth) * zoomFactor
    }
}

// MARK: - Float-space desaturation

/// Reduce an RGB color's saturation by `amount` (0 = unchanged,
/// 1 = gray) without any UIColor/NSColor allocation — the Metal
/// extraction path calls this once per node per rebuild. RGB → HSV,
/// scale S, back. Mirrors the Canvas path's
/// `Color.desaturated(by:)` (which goes through HSB on the
/// platform color type).
func desaturatedRGB(_ rgb: (Float, Float, Float),
                    by amount: Float) -> (Float, Float, Float) {
    guard amount > 0 else { return rgb }
    let (r, g, b) = rgb
    let maxC = max(r, max(g, b))
    let minC = min(r, min(g, b))
    let delta = maxC - minC
    guard maxC > 0, delta > 0 else { return rgb }   // gray already

    var h: Float
    if maxC == r {
        h = (g - b) / delta
        if h < 0 { h += 6 }
    } else if maxC == g {
        h = (b - r) / delta + 2
    } else {
        h = (r - g) / delta + 4
    }
    h /= 6

    let s = (delta / maxC) * (1 - min(1, max(0, amount)))
    let v = maxC

    let i = floor(h * 6)
    let f = h * 6 - i
    let p = v * (1 - s)
    let q = v * (1 - f * s)
    let t = v * (1 - (1 - f) * s)
    switch Int(i) % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}
