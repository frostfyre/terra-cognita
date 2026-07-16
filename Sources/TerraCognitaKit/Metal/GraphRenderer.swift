import Foundation
import Metal
import MetalKit
import simd

/// Metal "Pro" renderer for the graph canvas. The bulk geometry —
/// every edge and every node disc — goes through GPU-instanced draws
/// here. Selection halo, labels, hover affordances, and chrome stay
/// in SwiftUI as an overlay on top of the `MTKView` so we don't have
/// to reimplement text shaping or hit testing in Metal.
///
/// One draw call per layer (edges as a line list, nodes as instanced
/// quads), with all per-frame state living in compact GPU buffers.
/// At rest the renderer is event-driven (`isPaused = true`, redraw on
/// `setNeedsDisplay()`) so a static graph costs zero CPU.
final class GraphRenderer: NSObject, MTKViewDelegate {

    // MARK: - Inputs (set from main, drained at draw)

    /// World-space view transform. `tx`, `ty` are screen-pixel offsets
    /// from the viewport center; `scale` is the uniform zoom factor.
    /// The MTKView's drawable size resolves the rest.
    struct Camera: Equatable {
        var tx: CGFloat = 0
        var ty: CGFloat = 0
        var scale: CGFloat = 1
    }

    /// A node ready to be drawn. Laid out to match the Metal
    /// `NodeInstance` struct's 48-byte stride exactly — `float4 color`
    /// forces 16-byte alignment in the shader struct, so we co-opt
    /// what would otherwise be padding (`hashSeed`) to carry the
    /// per-node drift wobble seed. The shader reads it as
    /// `inst.radius.y`. The trailing `params` float4 carries the
    /// per-node era depth (parallax + drop shadow) and the
    /// light-fill flag (lit-from-upper-left highlight on foreground
    /// fills only).
    ///
    /// Color is the final display color: depth desaturation, depth
    /// opacity, and highlight dimming are baked in at extraction —
    /// they only change on graph / selection / hops changes, never
    /// per frame.
    struct NodeRenderable {
        var x: Float
        var y: Float
        var radius: Float
        var hashSeed: Float = 0    // 0..1, drives drift wobble in shader
        var r: Float
        var g: Float
        var b: Float
        var a: Float
        var depth: Float = 1       // era depth, 0 deep past … 1 present
        var lightFill: Float = 1   // 1 = paint the radial highlight
        var _p2: Float = 0
        var _p3: Float = 0
    }

    /// One vertex of the tessellated edge line list. Byte layout
    /// matches the shader's `EdgeVertexIn`: `position` (float2) @0,
    /// `seeds` (float2 = seed0,seed1) @8, `params` (float4 =
    /// depth0,depth1,t,pad) @16, `color` (float4) @32 — 48-byte
    /// stride, color 16-byte aligned. Every vertex along a curved
    /// edge carries both endpoint seeds + depths plus its own curve
    /// parameter `t`, so the shader can blend drift + parallax along
    /// the Bézier and keep the whole curve glued to its two nodes.
    struct EdgeVertex {
        var x: Float
        var y: Float
        var seed0: Float = 0
        var seed1: Float = 0
        var depth0: Float = 1
        var depth1: Float = 1
        var t: Float = 0
        var _pad: Float = 0
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    /// An edge ready to be drawn. Stored as two endpoints with their
    /// own colors + drift seeds + era depths, plus a stable per-edge
    /// `curveSign` (+1/-1) so the quadratic Bézier always bends the
    /// same way between frames — and A→B vs B→A bend opposite,
    /// keeping reciprocal edges distinct (mirrors the Canvas path).
    /// The renderer tessellates this into short segments at upload.
    struct EdgeRenderable {
        var x0: Float
        var y0: Float
        var seed0: Float
        var depth0: Float
        var r0: Float
        var g0: Float
        var b0: Float
        var a0: Float
        var x1: Float
        var y1: Float
        var seed1: Float
        var depth1: Float
        var r1: Float
        var g1: Float
        var b1: Float
        var a1: Float
        var curveSign: Float
    }

    /// Number of straight segments each edge's quadratic Bézier is
    /// tessellated into. 6 is smooth at the gentle 12%-of-length bend
    /// the Canvas path uses, without inflating the vertex buffer.
    static let edgeCurveSegments = 6

    /// One atmosphere speck — matches the shader's `SpeckInstance`
    /// (16 bytes). World-positioned, fixed screen-point radius,
    /// per-speck twinkle phase.
    struct SpeckRenderable {
        var x: Float
        var y: Float
        var radius: Float   // screen points, 0.6 – 1.6
        var phase: Float    // twinkle phase
    }

    // MARK: - GPU state

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let edgePipeline: MTLRenderPipelineState
    private let nodePipeline: MTLRenderPipelineState
    /// Second pass over the node instance buffer — feathered dark
    /// discs offset downward for foreground (depth > 0.5) nodes.
    private let nodeShadowPipeline: MTLRenderPipelineState
    /// Deep-background star-field, drawn first.
    private let speckPipeline: MTLRenderPipelineState
    /// Shared unit quad for instanced node draws. Four corners of [-1,+1]²
    /// in vertex order suitable for `triangleStrip`.
    private let quadVertexBuffer: MTLBuffer

    /// Vertex buffer for the edge line list — two `EdgeVertex`es per
    /// edge. Grown as needed; never shrunk to avoid realloc churn
    /// during interaction.
    private var edgeBuffer: MTLBuffer?
    /// Instance buffer for nodes. One `NodeInstance` per node.
    private var nodeInstanceBuffer: MTLBuffer?
    /// Instance buffer for atmosphere specks. Uploaded once per
    /// graph mount (the field is static).
    private var speckInstanceBuffer: MTLBuffer?
    private var edgeVertexCount: Int = 0
    private var nodeInstanceCount: Int = 0
    private var speckInstanceCount: Int = 0

    // MARK: - Per-frame state

    var camera: Camera = Camera()
    /// Drawable size in points, refreshed from `mtkView.drawableSize`.
    /// Stored separately so `update(camera:)` doesn't need an MTKView.
    private var viewportSize: SIMD2<Float> = .zero

    // MARK: - Init

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        // Transparent clear so the SwiftUI `RadialGradient` substrate
        // mounted underneath `GraphMetalView` shows through. Without
        // this, the Pro renderer paints over the gradient with a flat
        // midnight rectangle and loses the "echo of the app icon"
        // atmosphere the Canvas path establishes.
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        #if canImport(AppKit)
        mtkView.layer?.isOpaque = false
        #else
        mtkView.isOpaque = false
        mtkView.backgroundColor = .clear
        #endif
        // Continuous render while the "Pro" mode is still in beta.
        // Revisit once we've confirmed the perf envelope and we want
        // the event-driven energy win back.
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 120

        // Load shaders. Compiled from the embedded Swift string at
        // runtime rather than from `Bundle.module`'s default.metallib
        // — SwiftPM's .metal handling was producing an empty bundle
        // on this target (silent failure, then MTKView shows window
        // background through → all-white). Runtime compile is a
        // few-ms one-time cost on first use and is bulletproof.
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: GraphShaderSource.metal,
                                             options: nil)
        } catch {
            print("GraphRenderer: shader compile failed: \(error)")
            return nil
        }

        // Edge pipeline — line list, per-vertex color, alpha blending.
        let edgeDescriptor = MTLRenderPipelineDescriptor()
        edgeDescriptor.vertexFunction = library.makeFunction(name: "edge_vertex")
        edgeDescriptor.fragmentFunction = library.makeFunction(name: "edge_fragment")
        edgeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        Self.configureAlphaBlend(edgeDescriptor.colorAttachments[0]!)

        let edgeVertexDescriptor = MTLVertexDescriptor()
        // attribute(0) — position (float2) at offset 0
        edgeVertexDescriptor.attributes[0].format = .float2
        edgeVertexDescriptor.attributes[0].offset = 0
        edgeVertexDescriptor.attributes[0].bufferIndex = 0
        // attribute(2) — seeds (float2 = seed0, seed1) at offset 8 —
        // both endpoint drift seeds, blended along the curve.
        edgeVertexDescriptor.attributes[2].format = .float2
        edgeVertexDescriptor.attributes[2].offset = MemoryLayout<Float>.size * 2
        edgeVertexDescriptor.attributes[2].bufferIndex = 0
        // attribute(3) — params (float4 = depth0, depth1, t, pad) at
        // offset 16 — endpoint depths for parallax + the curve
        // parameter `t` used to blend drift/parallax along the edge.
        edgeVertexDescriptor.attributes[3].format = .float4
        edgeVertexDescriptor.attributes[3].offset = MemoryLayout<Float>.size * 4
        edgeVertexDescriptor.attributes[3].bufferIndex = 0
        // attribute(1) — color (float4) at offset 32 (16-byte aligned).
        edgeVertexDescriptor.attributes[1].format = .float4
        edgeVertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 8
        edgeVertexDescriptor.attributes[1].bufferIndex = 0
        edgeVertexDescriptor.layouts[0].stride = MemoryLayout<EdgeVertex>.stride
        edgeVertexDescriptor.layouts[0].stepFunction = .perVertex
        edgeDescriptor.vertexDescriptor = edgeVertexDescriptor

        // Node / shadow / speck pipelines — instanced quads. They
        // share the unit-quad vertex descriptor; per-instance data
        // comes in via buffer(2) indexed by instance_id.
        let quadVertexDescriptor = MTLVertexDescriptor()
        // attribute(0) — corner (float2), in the shared quad buffer
        quadVertexDescriptor.attributes[0].format = .float2
        quadVertexDescriptor.attributes[0].offset = 0
        quadVertexDescriptor.attributes[0].bufferIndex = 0
        quadVertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 2
        quadVertexDescriptor.layouts[0].stepFunction = .perVertex

        func instancedQuadDescriptor(vertex: String, fragment: String) -> MTLRenderPipelineDescriptor {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            Self.configureAlphaBlend(d.colorAttachments[0]!)
            d.vertexDescriptor = quadVertexDescriptor
            return d
        }
        let nodeDescriptor = instancedQuadDescriptor(vertex: "node_vertex",
                                                     fragment: "node_fragment")
        let shadowDescriptor = instancedQuadDescriptor(vertex: "node_shadow_vertex",
                                                       fragment: "node_shadow_fragment")
        let speckDescriptor = instancedQuadDescriptor(vertex: "speck_vertex",
                                                      fragment: "speck_fragment")

        do {
            self.edgePipeline = try device.makeRenderPipelineState(descriptor: edgeDescriptor)
            self.nodePipeline = try device.makeRenderPipelineState(descriptor: nodeDescriptor)
            self.nodeShadowPipeline = try device.makeRenderPipelineState(descriptor: shadowDescriptor)
            self.speckPipeline = try device.makeRenderPipelineState(descriptor: speckDescriptor)
        } catch {
            assertionFailure("GraphRenderer: pipeline build failed: \(error)")
            return nil
        }

        // Unit quad as a triangle strip — 4 vertices, no index buffer.
        var quad: [SIMD2<Float>] = [
            SIMD2(-1, -1), SIMD2( 1, -1),
            SIMD2(-1,  1), SIMD2( 1,  1)
        ]
        let quadByteCount = quad.count * MemoryLayout<SIMD2<Float>>.stride
        guard let qb = device.makeBuffer(bytes: &quad,
                                          length: quadByteCount,
                                          options: .storageModeShared) else {
            return nil
        }
        self.quadVertexBuffer = qb

        super.init()
        mtkView.delegate = self
    }

    private static func configureAlphaBlend(_ attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    // MARK: - Data updates

    /// Upload a new geometry set. Cheap when the counts haven't
    /// changed (buffer reused via `contents()` memcpy); allocates a
    /// new buffer only when growth is required.
    func update(nodes: [NodeRenderable], edges: [EdgeRenderable]) {
        uploadNodes(nodes)
        uploadEdges(edges)
    }

    /// Upload the atmosphere speck field. Called once per mount —
    /// the field is seeded deterministically and never changes.
    func updateSpecks(_ specks: [SpeckRenderable]) {
        speckInstanceCount = specks.count
        guard !specks.isEmpty else { return }
        let stride = MemoryLayout<SpeckRenderable>.stride
        let needed = specks.count * stride
        if (speckInstanceBuffer?.length ?? 0) < needed {
            speckInstanceBuffer = device.makeBuffer(
                length: needed,
                options: .storageModeShared)
        }
        guard let buffer = speckInstanceBuffer else { return }
        specks.withUnsafeBufferPointer { src in
            memcpy(buffer.contents(), src.baseAddress, needed)
        }
    }

    private func uploadNodes(_ nodes: [NodeRenderable]) {
        nodeInstanceCount = nodes.count
        guard !nodes.isEmpty else { return }
        let stride = MemoryLayout<NodeRenderable>.stride
        let needed = nodes.count * stride
        if (nodeInstanceBuffer?.length ?? 0) < needed {
            nodeInstanceBuffer = device.makeBuffer(
                length: max(needed, stride * 1024),
                options: .storageModeShared)
        }
        guard let buffer = nodeInstanceBuffer else { return }
        nodes.withUnsafeBufferPointer { src in
            memcpy(buffer.contents(), src.baseAddress, needed)
        }
    }

    private func uploadEdges(_ edges: [EdgeRenderable]) {
        // Each edge is tessellated into `edgeCurveSegments` straight
        // segments along a quadratic Bézier — 2 vertices per segment
        // (line list). The control point is offset perpendicular to
        // the chord by 12% of its length, on the side picked by the
        // stable per-edge `curveSign`, mirroring the Canvas path's
        // `edgePath`.
        let segs = Self.edgeCurveSegments
        edgeVertexCount = edges.count * 2 * segs
        guard !edges.isEmpty else { return }
        let stride = MemoryLayout<EdgeVertex>.stride
        let needed = edges.count * 2 * segs * stride
        if (edgeBuffer?.length ?? 0) < needed {
            edgeBuffer = device.makeBuffer(
                length: max(needed, stride * 4096),
                options: .storageModeShared)
        }
        guard let buffer = edgeBuffer else { return }
        let ptr = buffer.contents().assumingMemoryBound(to: EdgeVertex.self)
        var i = 0
        for e in edges {
            let p0 = SIMD2<Float>(e.x0, e.y0)
            let p1 = SIMD2<Float>(e.x1, e.y1)
            let d = p1 - p0
            let len = max((d.x * d.x + d.y * d.y).squareRoot(), 1)
            let bend = len * 0.12 * e.curveSign
            let perp = SIMD2<Float>(-d.y / len, d.x / len)
            let ctrl = (p0 + p1) * 0.5 + perp * bend
            // Quadratic Bézier sample + per-t color lerp.
            func point(_ t: Float) -> SIMD2<Float> {
                let mt = 1 - t
                return mt * mt * p0 + 2 * mt * t * ctrl + t * t * p1
            }
            func vertex(_ t: Float) -> EdgeVertex {
                let p = point(t)
                return EdgeVertex(
                    x: p.x, y: p.y,
                    seed0: e.seed0, seed1: e.seed1,
                    depth0: e.depth0, depth1: e.depth1,
                    t: t, _pad: 0,
                    r: e.r0 + (e.r1 - e.r0) * t,
                    g: e.g0 + (e.g1 - e.g0) * t,
                    b: e.b0 + (e.b1 - e.b0) * t,
                    a: e.a0 + (e.a1 - e.a0) * t)
            }
            for s in 0..<segs {
                ptr[i]     = vertex(Float(s)     / Float(segs))
                ptr[i + 1] = vertex(Float(s + 1) / Float(segs))
                i += 2
            }
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2(Float(size.width), Float(size.height))
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        // Bail before acquiring a drawable when the view hasn't been
        // sized yet (cold-start, hidden tab, off-screen window). If
        // we proceeded, `currentDrawable` would still hand back a
        // drawable but encoder creation against a 0-size attachment
        // fails — and the drawable we acquired never gets
        // presented + committed, so it leaks. After 3 frames the
        // drawable pool is exhausted and `currentDrawable` deadlocks
        // the main thread on `dispatch_semaphore_wait_slow`. Skipping
        // when the view has no size keeps the pool intact.
        if view.drawableSize.width < 1 || view.drawableSize.height < 1 { return }

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        if viewportSize == .zero {
            viewportSize = SIMD2(Float(view.drawableSize.width),
                                 Float(view.drawableSize.height))
        }

        // Build uniforms — world → clip transform. Clip space is
        // [-1, +1]² with +Y up; our world matches CoreGraphics with
        // +Y *down*, so flip Y in the clip step. Camera applies pan
        // (in pixels at the current scale) and zoom in world space.
        let drawableSize = view.drawableSize
        let viewW = Float(drawableSize.width)
        let viewH = Float(drawableSize.height)
        // Backing scale — drawable is in pixels, camera pan in points.
        let backingScale: Float = max(
            Float(view.contentScaleFactor_compat()), 1.0)
        let s = Float(camera.scale)
        // Compose the matrix: world → centered pixels → clip.
        //
        //   pixel_x = (world_x * s) + (tx + viewW/(2*backing)) [in points]
        //   clip_x  = pixel_x / (viewW / backing) * 2 - 1
        //
        // After algebra, the matrix coefficients are:
        let kx = (2.0 * s * backingScale) / viewW
        let ky = -(2.0 * s * backingScale) / viewH
        let tx = (2.0 * Float(camera.tx) * backingScale) / viewW
        let ty = -(2.0 * Float(camera.ty) * backingScale) / viewH
        let worldToClip = float4x4(
            SIMD4<Float>(kx, 0,  0, 0),
            SIMD4<Float>(0,  ky, 0, 0),
            SIMD4<Float>(0,  0,  1, 0),
            SIMD4<Float>(tx, ty, 0, 1)
        )

        // Uniform viewport is in POINTS (not pixels). The drift
        // wobble shader divides world-space pixel offsets by this
        // viewport to land in NDC; using pixels would shrink the
        // wobble by `backingScale` on retina displays.
        let pointViewW = viewW / backingScale
        let pointViewH = viewH / backingScale
        var uniforms = Uniforms(
            worldToClip: worldToClip,
            viewportSize: SIMD2(pointViewW, pointViewH),
            // Process-shared clock so SwiftUI overlays (labels,
            // selection halo, hover ring) can compute matching drift
            // offsets against the same `t` value.
            time: GraphDrift.nowFloat(),
            scale: s,
            // Camera pan in points — the shader's per-vertex parallax
            // subtracts a depth-dependent share of this from the full
            // pan baked into `worldToClip`.
            cameraTranslate: SIMD2(Float(camera.tx), Float(camera.ty)),
            _pad: .zero
        )

        func bindQuadPass(_ pipeline: MTLRenderPipelineState,
                          instances: MTLBuffer,
                          count: Int) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride,
                                   index: 1)
            encoder.setVertexBuffer(instances, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangleStrip,
                                   vertexStart: 0,
                                   vertexCount: 4,
                                   instanceCount: count)
        }

        // Draw order mirrors the Canvas path's painter's algorithm:
        // atmosphere specks (deepest), edges, node drop shadows,
        // node discs.
        if let speckInstanceBuffer, speckInstanceCount > 0 {
            bindQuadPass(speckPipeline,
                         instances: speckInstanceBuffer,
                         count: speckInstanceCount)
        }

        // Edges — line list, one draw call.
        if let edgeBuffer, edgeVertexCount > 0 {
            encoder.setRenderPipelineState(edgePipeline)
            encoder.setVertexBuffer(edgeBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride,
                                   index: 1)
            encoder.drawPrimitives(type: .line,
                                   vertexStart: 0,
                                   vertexCount: edgeVertexCount)
        }

        // Nodes — shadow pass, then the discs themselves.
        if let nodeInstanceBuffer, nodeInstanceCount > 0 {
            bindQuadPass(nodeShadowPipeline,
                         instances: nodeInstanceBuffer,
                         count: nodeInstanceCount)
            bindQuadPass(nodePipeline,
                         instances: nodeInstanceBuffer,
                         count: nodeInstanceCount)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Uniforms layout (matches GraphShaderSource)

    private struct Uniforms {
        var worldToClip: float4x4
        var viewportSize: SIMD2<Float>
        var time: Float
        var scale: Float
        var cameraTranslate: SIMD2<Float>
        var _pad: SIMD2<Float>
    }
}

// MARK: - Cross-platform backing-scale shim

#if canImport(AppKit)
import AppKit
extension MTKView {
    fileprivate func contentScaleFactor_compat() -> CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }
}
#endif
#if canImport(UIKit)
import UIKit
extension MTKView {
    fileprivate func contentScaleFactor_compat() -> CGFloat {
        contentScaleFactor
    }
}
#endif
