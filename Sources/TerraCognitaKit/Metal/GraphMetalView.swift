import SwiftUI
import MetalKit

#if canImport(AppKit)
import AppKit
typealias _ViewRepresentable = NSViewRepresentable
#endif
#if canImport(UIKit)
import UIKit
typealias _ViewRepresentable = UIViewRepresentable
#endif

/// SwiftUI host for the Metal "Pro" renderer. Wraps an `MTKView` and
/// a `GraphRenderer`. All input — pan, pinch, tap, node drag,
/// long-press, Connect mode — comes from a transparent SwiftUI
/// overlay above the metal layer, which keeps the gesture surface
/// identical to `GraphCanvasView` while dropping the CPU-bound
/// Canvas pipeline.
///
/// Feature parity with the Canvas path:
///   • GPU: node discs (depth cues + light-fill + zoom-coupled
///     radius), edges (per-endpoint gradient colors + dim/bright
///     z-order), depth drop shadows, atmosphere specks, drift
///     wobble, depth parallax.
///   • SwiftUI overlays: labels, selection halo (breath + sparks +
///     pulsing core), hover ring, ambient idle puff, bridge rings,
///     hero images, connect rubber band.
///   • Interaction: N-hop highlight dimming, node drag, long-press
///     radials, shift-drag Connect (macOS), sticky selection,
///     fit-to-view, layout switching.
struct GraphMetalView: View {
    @ObservedObject var store: GraphStore
    /// Owned by `GraphView` so the inspector panel can drive it too.
    @Binding var selectedNodeID: String?
    /// A node freshly written by `GraphStore.createNode`. We pin it
    /// at its spawn world point, select it, frame onto it, then
    /// clear the binding — same contract as the Canvas path.
    @Binding var pendingNewNode: PendingNewNode?
    /// Optional node-visibility filter (lens). `nil` shows everything.
    /// Edges are visible only when both endpoints pass the filter.
    var visibleNodeFilter: ((Node) -> Bool)? = nil
    /// Fires when the user long-presses *empty* canvas. Carries world
    /// + screen coordinates so the host can spawn content and anchor
    /// a radial menu.
    var onLongPressEmptyWorld: ((_ worldPoint: CGPoint, _ screenPoint: CGPoint) -> Void)?
    /// Fires when the user long-presses *on a node* — host opens the
    /// per-node radial menu.
    var onLongPressNode: ((_ nodeID: String, _ screenPoint: CGPoint) -> Void)?
    /// "Fit to view" pulse channel — host increments to request a
    /// refit (⌘0, post-load auto-frame).
    @Binding var frameAllPulse: Int
    /// The algorithm currently applied — surfaced upward so the
    /// Layout menu can show a checkmark.
    @Binding var layoutAlgorithm: LayoutAlgorithm?
    /// When true, layout passes run the iterative push-apart
    /// post-pass so no nodes overlap.
    @Binding var noOverlap: Bool
    /// Pulse channel for "user picked a layout from the menu".
    @Binding var layoutRequest: LayoutAlgorithm?
    /// How many BFS hops from the selected node stay at full opacity.
    @Binding var highlightDepth: Int
    /// Source node id while a spatial "Connect" gesture is armed.
    @Binding var connectingFromID: String?
    /// Fired when the user taps empty canvas in Connect mode — the
    /// host opens `AddNodeSheet` seeded with a link to the source.
    var onConnectDropEmpty: ((_ sourceID: String, _ worldPoint: CGPoint) -> Void)?
    /// Node ids highlighted as topology bridges (Systems lens).
    var bridgeNodeIDs: Set<String> = []

    // MARK: - Camera / input state

    @State private var camera = GraphRenderer.Camera()
    @State private var lastPanTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    /// Camera zoom clamps. The floor is intentionally tiny so the
    /// Fit action (and manual pinch) can frame very large graphs —
    /// 15k+ nodes spread wide by force-direction need to zoom out
    /// well past the old 0.05 floor, which couldn't fit them.
    private let minCameraScale: CGFloat = 0.002
    private let maxCameraScale: CGFloat = 8.0
    /// Currently-hovered node id (Mac mouse, iPad pointer).
    @State private var hoveredNodeID: String?
    /// While the user is dragging a node, its id; `nodeDragStartWorld`
    /// anchors the translation so the node moves exactly with the
    /// finger.
    @State private var draggingNodeID: String?
    @State private var nodeDragStartWorld: CGPoint?
    /// True while the active drag is panning empty canvas.
    @State private var isPanningCanvas = false
    /// In-flight camera animation (frame-to-fit, frame-on-select).
    @State private var cameraAnimTask: Task<Void, Never>?
    /// In-flight layout-transition animation (layout switch).
    @State private var layoutAnimTask: Task<Void, Never>?
    /// In-flight force-directed compute, cancellable on re-request.
    @State private var layoutComputeTask: Task<[String: CGPoint], Never>?

    // MARK: - Graph caches

    /// Undirected adjacency + degree table, rebuilt when the graph
    /// changes. Drives the N-hop highlight BFS, degree-coupled radii
    /// (without an O(E) walk per node), and the ambient pick weights.
    @State private var adjacency: [String: [String]] = [:]
    /// Nodes sorted back-to-front by era depth so hit-testing can
    /// walk front-to-back and the GPU draws past-behind-present.
    @State private var depthOrderedNodes: [Node] = []
    /// Current N-hop BFS neighborhood of the selection (empty when
    /// nothing is selected). Shared with the labels overlay.
    @State private var highlightSet: Set<String> = []

    /// Cached renderables — rebuilt only when the graph, layout,
    /// selection, or hops change, NOT on every body re-evaluation.
    /// Without this cache an fps tick would invalidate the whole
    /// 15K-node extraction → buffer re-upload pipeline twice per
    /// second and pin main-thread CPU.
    @State private var cachedNodes: [GraphRenderer.NodeRenderable] = []
    @State private var cachedEdges: [GraphRenderer.EdgeRenderable] = []
    /// Bumped each time `rebuildRenderables` writes new caches.
    @State private var dataRevision: Int = 0
    /// Deep-background star-field, seeded once per mount.
    @State private var cachedSpecks: [GraphRenderer.SpeckRenderable] = []
    @State private var speckRevision: Int = 0

    // MARK: - Ambient idle animation

    /// When nothing is selected, a random node periodically "puffs"
    /// so the graph feels alive — mirrors the Canvas path.
    @State private var ambientHighlightID: String?
    @State private var ambientHighlightStart: TimeInterval?

    /// Coordinator handle so the SwiftUI overlay's gestures can ask
    /// the renderer for redraws without re-evaluating the body.
    @StateObject private var bridge = MetalBridge()

    private static let selectionGold = Color(red: 1.00, green: 0.78, blue: 0.30)

    var body: some View {
        GeometryReader { geo in
            let projection = GraphProjection(camera: camera, viewSize: geo.size)
            ZStack {
                // Substrate gradient — same deep indigo → near-black
                // radial field the Canvas path uses, so toggling the
                // bolt doesn't change the world the graph sits inside.
                RadialGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.28),
                        Color(red: 0.02, green: 0.02, blue: 0.05)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.85
                )
                .ignoresSafeArea()
                MetalContainer(bridge: bridge,
                               camera: camera,
                               nodes: cachedNodes,
                               edges: cachedEdges,
                               specks: cachedSpecks,
                               dataRevision: dataRevision,
                               speckRevision: speckRevision)
                GraphAmbientPuffOverlay(store: store,
                                        ambientNodeID: selectedNodeID == nil ? ambientHighlightID : nil,
                                        startTime: ambientHighlightStart,
                                        projection: projection)
                GraphBridgeRingsOverlay(store: store,
                                        bridgeNodeIDs: bridgeNodeIDs,
                                        visibleNodeFilter: visibleNodeFilter,
                                        projection: projection)
                GraphHeroImagesOverlay(store: store,
                                       projection: projection,
                                       visibleNodeFilter: visibleNodeFilter,
                                       nodeWorldRadius: { nodeWorldRadius($0) })
                GraphHoverRingOverlay(store: store,
                                      hoveredNodeID: hoveredNodeID,
                                      projection: projection)
                GraphSelectionHaloOverlay(store: store,
                                          selectedNodeID: selectedNodeID,
                                          projection: projection)
                GraphLabelsOverlay(store: store,
                                   projection: projection,
                                   visibleNodeFilter: visibleNodeFilter,
                                   selectedNodeID: selectedNodeID,
                                   highlight: highlightSet)
                inputOverlay(geo: geo)
                if bridge.rendererFailed {
                    rendererFailureOverlay
                }
                if FPSReadout.enabled {
                    FPSOverlay(bridge: bridge)
                }
            }
            .overlay(alignment: .topLeading) {
                connectRubberBand(projection: projection)
                    .allowsHitTesting(false)
            }
            #if os(macOS)
            .contextMenu { selectedNodeMenu() }
            #endif
            .onAppear {
                seedAtmosphereSpecks()
            }
            // The layout pipeline runs HERE, not in GraphCanvasView —
            // so the Metal path drives both layout and the loading-
            // screen dismissal on its own. The splash is gated on
            // `store.layoutSettleTick`, which was previously bumped
            // ONLY by GraphCanvasView's pipeline; since that view
            // isn't mounted in bolt mode, leaving the app in bolt
            // mode meant nothing ever advanced the tick and the
            // splash hung indefinitely. `.task(id:)` re-runs on node-
            // count changes and on every remount (chrome remounts us
            // on `renderRevision`), mirroring the Canvas path's
            // `.task(id: nodes.count)`.
            .task(id: store.graph.nodes.count) {
                await runLayoutPipeline()
            }
            // Selection / hops drive the highlight dimming, which is
            // baked into the instance colors — rebuild WITHOUT
            // refitting the camera (framing is its own animation).
            .onChange(of: selectedNodeID) { _, newValue in
                rebuildRenderables()
                if newValue != nil {
                    frameHighlightedSubnet(size: geo.size)
                    // Cancel any in-flight ambient puff so it doesn't
                    // fight the user's deliberate selection.
                    ambientHighlightID = nil
                    ambientHighlightStart = nil
                    Haptics.tap(.light)
                }
            }
            .onChange(of: highlightDepth) { _, _ in
                rebuildRenderables()
            }
            .onChange(of: frameAllPulse) { _, _ in
                if selectedNodeID != nil {
                    frameHighlightedSubnet(size: geo.size)
                } else {
                    frameAllVisible(size: geo.size)
                }
            }
            .onChange(of: layoutRequest) { _, newValue in
                guard let algorithm = newValue else { return }
                Task { @MainActor in
                    await applyLayout(algorithm)
                    layoutRequest = nil
                }
            }
            .onChange(of: noOverlap) { oldValue, newValue in
                guard oldValue != newValue, newValue else {
                    if oldValue != newValue { persistLayout() }
                    return
                }
                let fixed = LayoutEngine.enforceNoOverlap(store.nodePositions)
                animatePositions(to: fixed)
                persistLayout()
            }
            .onChange(of: pendingNewNode) { _, newValue in
                guard let pending = newValue else { return }
                consumePendingNewNode(pending, size: geo.size)
            }
            .task { await runAmbientCycle() }
        }
    }

    private func rebuildRenderables() {
        highlightSet = highlightedNodeIDs()
        cachedNodes = nodeRenderables()
        cachedEdges = edgeRenderables()
        dataRevision &+= 1
    }

    /// Rebuild adjacency / degree / depth-order caches. O(N + E);
    /// called on graph mutations only.
    private func rebuildGraphCaches() {
        var adj: [String: [String]] = [:]
        adj.reserveCapacity(store.graph.nodes.count)
        for edge in store.graph.edges {
            adj[edge.sourceID, default: []].append(edge.targetID)
            adj[edge.targetID, default: []].append(edge.sourceID)
        }
        adjacency = adj
        depthOrderedNodes = store.graph.nodes.values
            .sorted { $0.depth(in: store.config) < $1.depth(in: store.config) }
    }

    /// Visible failure mode for when `GraphRenderer.init?` returns
    /// nil. Without this the MTKView stays unpainted and the user
    /// just sees the window background (white on macOS) — a failure
    /// indistinguishable from a successful "empty graph" render.
    @ViewBuilder
    private var rendererFailureOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)
            Text("Pro renderer failed to initialize")
                .font(.headline)
            Text("Falling back to the Canvas renderer is safe — toggle the bolt button off in the top bar. Check Console.app for shader / Metal errors.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .padding(20)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Renderer-agnostic layout pipeline for the Metal path — the
    /// counterpart to `GraphCanvasView.rebuildLayoutPipeline`. Picks
    /// the cheapest correct source of positions, then ALWAYS advances
    /// `store.layoutSettleTick` so the loading screen dismisses (the
    /// bug this fixes: in bolt mode nothing advanced the tick, so the
    /// splash hung).
    ///
    /// Order of preference:
    ///   (a) positions already in the store (e.g. the user toggled
    ///       over from the Canvas path mid-session) — reuse as-is.
    ///   (b) a persisted layout covering the whole node set — restore
    ///       it AND the camera, instantly (the common relaunch case).
    ///   (c) otherwise circular-seed for an immediate picture, then
    ///       swap in a background force-directed layout.
    private func runLayoutPipeline() async {
        layoutComputeTask?.cancel()
        layoutComputeTask = nil
        rebuildGraphCaches()

        let nodeIDs = Array(store.graph.nodes.keys)
        guard !nodeIDs.isEmpty else {
            store.nodePositions = [:]
            rebuildRenderables()
            store.layoutSettleTick &+= 1
            return
        }
        let nodeSet = Set(nodeIDs)
        let persisted = LayoutPersistence.load()

        // Restore the persisted camera on any reuse path — this @State
        // resets to the default on every remount (chrome remounts us
        // on `renderRevision`), so without this a mid-session config
        // edit would snap the view back to origin / scale 1.
        func restorePersistedCamera() {
            guard let p = persisted else { return }
            camera = GraphRenderer.Camera(
                tx: CGFloat(p.offsetX),
                ty: CGFloat(p.offsetY),
                scale: max(minCameraScale, min(maxCameraScale, CGFloat(p.scale))))
        }

        // (a) Already laid out this session.
        if nodeSet.isSubset(of: Set(store.nodePositions.keys)) {
            restorePersistedCamera()
            rebuildRenderables()
            store.layoutSettleTick &+= 1
            return
        }

        // (b) Persisted layout covers the node set — fast restore.
        if let persisted, nodeSet.isSubset(of: Set(persisted.cgPositions.keys)) {
            var restored = persisted.cgPositions
            noOverlap = persisted.noOverlap ?? false
            if noOverlap { restored = LayoutEngine.enforceNoOverlap(restored) }
            store.nodePositions = restored
            restorePersistedCamera()
            layoutAlgorithm = persisted.algorithm ?? .forceDirected
            if let d = persisted.highlightDepth { highlightDepth = max(1, min(4, d)) }
            rebuildRenderables()
            store.layoutSettleTick &+= 1
            return
        }

        // (c) Fresh: circular seed first so the splash dismisses onto
        // a real picture, then the force-directed pass swapped in.
        let edgePairs = store.graph.edges.map { ($0.sourceID, $0.targetID) }
        store.nodePositions = makeCircularLayout(for: nodeIDs)
        layoutAlgorithm = .circular
        rebuildRenderables()

        let solver = ForceDirectedLayout()
        let task = Task.detached(priority: .userInitiated) {
            solver.compute(nodeIDs: nodeIDs, edges: edgePairs)
        }
        layoutComputeTask = task
        let computed = await task.value
        // Bail if a newer pipeline cancelled us or the graph was
        // replaced — but still dismiss the splash; the seed is shown.
        guard !task.isCancelled,
              store.graph.nodes.count == nodeIDs.count else {
            store.layoutSettleTick &+= 1
            return
        }
        let next = noOverlap ? LayoutEngine.enforceNoOverlap(computed) : computed
        animatePositions(to: next)
        layoutAlgorithm = .forceDirected
        persistLayout(positions: next)
        store.layoutSettleTick &+= 1
    }

    private func makeCircularLayout(for ids: [String]) -> [String: CGPoint] {
        let count = max(ids.count, 1)
        let radius = CGFloat(280 + min(ids.count, 600) / 2)
        var new: [String: CGPoint] = [:]
        new.reserveCapacity(count)
        for (i, id) in ids.enumerated() {
            let angle = 2 * .pi * CGFloat(i) / CGFloat(count)
            new[id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        return new
    }

    /// Deterministic background speck field — identical constants to
    /// the Canvas path (count, extent, radii, seed) so toggling the
    /// bolt keeps the same sky.
    private func seedAtmosphereSpecks() {
        guard cachedSpecks.isEmpty else { return }
        var rng = SplitMix64Speck(seed: 0xC0FFEE_CAFE_BEEF)
        let count = 140
        let halfWidth: Double = 4000
        let halfHeight: Double = 3000
        cachedSpecks = (0..<count).map { _ in
            GraphRenderer.SpeckRenderable(
                x: Float((rng.nextUnit() * 2 - 1) * halfWidth),
                y: Float((rng.nextUnit() * 2 - 1) * halfHeight),
                radius: Float(0.6 + rng.nextUnit() * 1.0),
                phase: Float(rng.nextUnit() * 6.28318)
            )
        }
        speckRevision &+= 1
    }

    // MARK: - Camera fitting / framing

    /// Ease the camera to `target` over `duration`. The camera is a
    /// plain struct read imperatively by the renderer, so SwiftUI's
    /// `withAnimation` can't interpolate it — we drive the tween
    /// ourselves at ~60 Hz.
    private func animateCamera(to target: GraphRenderer.Camera,
                               duration: Double = 0.55) {
        cameraAnimTask?.cancel()
        let from = camera
        let start = CACurrentMediaTime()
        cameraAnimTask = Task { @MainActor in
            while !Task.isCancelled {
                let raw = (CACurrentMediaTime() - start) / duration
                if raw >= 1 { break }
                // easeInOut
                let t = CGFloat(0.5 - 0.5 * cos(.pi * raw))
                camera = GraphRenderer.Camera(
                    tx: from.tx + (target.tx - from.tx) * t,
                    ty: from.ty + (target.ty - from.ty) * t,
                    scale: from.scale + (target.scale - from.scale) * t)
                bridge.needsDisplay()
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled {
                camera = target
                bridge.needsDisplay()
            }
        }
    }

    /// Animate the camera so the highlighted set (selected node +
    /// N-hop neighbors) fits with padding, selected node centered.
    /// Ports `GraphCanvasView.frameHighlightedSubnet` — including
    /// the parallax-correct centering for background-era selections.
    private func frameHighlightedSubnet(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let highlighted = highlightedNodeIDs()
        let points = highlighted.compactMap { store.nodePositions[$0] }
        guard !points.isEmpty else { return }

        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let centerWorld: CGPoint = {
            if let sel = selectedNodeID, let p = store.nodePositions[sel] {
                return p
            }
            return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        }()
        let centerPF: CGFloat = {
            if let sel = selectedNodeID,
               let node = store.graph.nodes[sel] {
                return GraphProjection.parallaxFactor(
                    depth: node.depth(in: store.config))
            }
            return 1.0
        }()
        let halfWidthWorld  = max(centerWorld.x - minX, maxX - centerWorld.x)
        let halfHeightWorld = max(centerWorld.y - minY, maxY - centerWorld.y)
        let widthWorld  = max(halfWidthWorld * 2, 1)
        let heightWorld = max(halfHeightWorld * 2, 1)

        let chromePadding: CGFloat = 60
        let labelMargin:   CGFloat = 80
        let inset = chromePadding + labelMargin
        let availableWidth  = max(size.width  - inset * 2, 200)
        let availableHeight = max(size.height - inset * 2, 200)

        let candidate = min(availableWidth / widthWorld,
                            availableHeight / heightWorld)
        let targetScale = max(0.4, min(candidate, 2.2))

        animateCamera(to: GraphRenderer.Camera(
            tx: -centerWorld.x * targetScale / centerPF,
            ty: -centerWorld.y * targetScale / centerPF,
            scale: targetScale))
    }

    /// Animate the camera so every currently-visible node fits with
    /// padding — ⌘0 / Fit wedge. Zoom capped at 2.2× so a sparse
    /// cluster doesn't fill the viewport with a wall of nodes.
    private func frameAllVisible(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
            Set(store.graph.nodes.values.filter(filter).map(\.id))
        }
        let candidateIDs: [String] = {
            if let visibleSet { return Array(visibleSet) }
            return Array(store.graph.nodes.keys)
        }()
        let points = candidateIDs.compactMap { store.nodePositions[$0] }
        guard !points.isEmpty else { return }

        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let centerWorld = CGPoint(x: (minX + maxX) / 2,
                                  y: (minY + maxY) / 2)
        let widthWorld  = max(maxX - minX, 1)
        let heightWorld = max(maxY - minY, 1)

        let chromePadding: CGFloat = 80
        let labelMargin:   CGFloat = 80
        let inset = chromePadding + labelMargin
        let availableWidth  = max(size.width  - inset * 2, 200)
        let availableHeight = max(size.height - inset * 2, 200)

        let candidate = min(availableWidth / widthWorld,
                            availableHeight / heightWorld)
        let targetScale = max(minCameraScale, min(candidate, 2.2))

        animateCamera(to: GraphRenderer.Camera(
            tx: -centerWorld.x * targetScale,
            ty: -centerWorld.y * targetScale,
            scale: targetScale))
    }

    // MARK: - Spatial node-creation handoff

    /// Pin the new node at its spawn world point (or near the current
    /// selection / origin), select it, frame onto it, clear the
    /// binding — same contract as the Canvas path.
    private func consumePendingNewNode(_ pending: PendingNewNode, size: CGSize) {
        let spawn: CGPoint = {
            if let p = pending.worldPoint { return p }
            if let sel = selectedNodeID, sel != pending.id,
               let p = store.nodePositions[sel] {
                return CGPoint(x: p.x + 90, y: p.y + 30)
            }
            return .zero
        }()
        store.nodePositions[pending.id] = spawn
        selectedNodeID = pending.id
        rebuildGraphCaches()
        rebuildRenderables()
        persistLayout()
        Task { @MainActor in
            await Task.yield()
            frameHighlightedSubnet(size: size)
        }
        pendingNewNode = nil
    }

    // MARK: - Idle / ambient animation

    /// Background loop that periodically picks a random node and
    /// puffs it when the user is idle (no selection). One puff at a
    /// time, spaced 3.5–6.5 seconds apart.
    private func runAmbientCycle() async {
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            let pause = Double.random(in: 3.5...6.5)
            try? await Task.sleep(for: .seconds(pause))
            if Task.isCancelled { break }
            guard selectedNodeID == nil, !store.graph.nodes.isEmpty else { continue }
            let nodes = Array(store.graph.nodes.values)
            let chosen = pickWeightedNode(from: nodes) ?? nodes.randomElement()
            guard let id = chosen?.id, id != ambientHighlightID else { continue }
            ambientHighlightID = id
            ambientHighlightStart = GraphDrift.now()
        }
    }

    /// Weighted random pick: prefer nodes with more connections.
    private func pickWeightedNode(from nodes: [Node]) -> Node? {
        let weights = nodes.map { 1 + (adjacency[$0.id]?.count ?? 0) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        let target = Int.random(in: 0..<total)
        var running = 0
        for (i, w) in weights.enumerated() {
            running += w
            if running > target { return nodes[i] }
        }
        return nodes.last
    }

    // MARK: - Layout switching

    /// Switch to a specific layout algorithm — port of the Canvas
    /// path's `applyLayout`, animating positions across so the user
    /// keeps spatial memory through the transition.
    private func applyLayout(_ algorithm: LayoutAlgorithm) async {
        let nodeIDs = Array(store.graph.nodes.keys)
        guard !nodeIDs.isEmpty else { return }
        let edgePairs = store.graph.edges.map { ($0.sourceID, $0.targetID) }

        let computed: [String: CGPoint]
        switch algorithm {
        case .forceDirected:
            layoutComputeTask?.cancel()
            let solver = ForceDirectedLayout()
            let task = Task.detached(priority: .userInitiated) {
                solver.compute(nodeIDs: nodeIDs, edges: edgePairs)
            }
            layoutComputeTask = task
            let result = await task.value
            guard !task.isCancelled else { return }
            computed = result
        case .circular:
            let count = max(nodeIDs.count, 1)
            let radius = CGFloat(280 + min(nodeIDs.count, 600) / 2)
            var new: [String: CGPoint] = [:]
            for (i, id) in nodeIDs.enumerated() {
                let angle = 2 * .pi * CGFloat(i) / CGFloat(count)
                new[id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            }
            computed = new
        case .grid:
            computed = LayoutEngine.grid(nodeIDs: nodeIDs)
        case .radial:
            computed = LayoutEngine.radial(
                nodeIDs: nodeIDs,
                adjacency: adjacency,
                root: selectedNodeID
            )
        case .hierarchical:
            computed = LayoutEngine.hierarchical(
                nodeIDs: nodeIDs,
                adjacency: adjacency,
                root: selectedNodeID
            )
        case .cluster:
            let graphSnapshot = store.graph
            computed = await Task.detached(priority: .userInitiated) {
                let partition = GraphAnalysis.communityPartition(of: graphSnapshot)
                return LayoutEngine.cluster(
                    nodeIDs: nodeIDs,
                    edges: edgePairs,
                    partition: partition
                )
            }.value
        case .timeline:
            let allNodes = Array(store.graph.nodes.values)
            let eraTable: [String: Double] = store.config.eras.reduce(into: [:]) {
                $0[$1.name.lowercased()] = $1.weight
            }
            computed = LayoutEngine.timeline(
                nodes: allNodes,
                eraWeights: eraTable
            )
        }

        guard store.graph.nodes.count == nodeIDs.count else { return }
        var next = computed
        if noOverlap {
            next = LayoutEngine.enforceNoOverlap(next)
        }
        animatePositions(to: next)
        layoutAlgorithm = algorithm
        persistLayout(positions: next)
    }

    /// Ease every node from its current position toward `target`
    /// over `duration`, rebuilding the GPU buffers per tick. The
    /// Canvas path interpolates inside its 20 Hz draw closure; here
    /// the geometry lives in GPU buffers, so we re-extract at ~30 Hz
    /// for the transition's duration (a bounded, transient cost).
    private func animatePositions(to target: [String: CGPoint],
                                  duration: Double = 0.8) {
        layoutAnimTask?.cancel()
        let from = store.nodePositions
        let start = CACurrentMediaTime()
        layoutAnimTask = Task { @MainActor in
            while !Task.isCancelled {
                let raw = (CACurrentMediaTime() - start) / duration
                if raw >= 1 { break }
                // easeOutQuart — fast settle without overshoot.
                let alpha = 1 - pow(1 - min(1, max(0, raw)), 4)
                var blended = target
                for (id, to) in target {
                    if let f = from[id] {
                        blended[id] = CGPoint(
                            x: f.x + (to.x - f.x) * alpha,
                            y: f.y + (to.y - f.y) * alpha)
                    }
                }
                store.nodePositions = blended
                rebuildRenderables()
                try? await Task.sleep(for: .milliseconds(33))
            }
            if !Task.isCancelled {
                store.nodePositions = target
                rebuildRenderables()
            }
        }
    }

    /// Snapshot current layout + view state and persist to disk.
    /// The Metal camera shares the Canvas path's `(scale, offset)`
    /// semantics, so persisted layouts round-trip between renderers.
    private func persistLayout(positions: [String: CGPoint]? = nil) {
        var snapshot = PersistedLayout()
        snapshot.positions = (positions ?? store.nodePositions)
            .mapValues(PersistedLayout.Point.init)
        snapshot.scale = Double(camera.scale)
        snapshot.offsetX = Double(camera.tx)
        snapshot.offsetY = Double(camera.ty)
        snapshot.algorithm = layoutAlgorithm
        snapshot.noOverlap = noOverlap
        snapshot.highlightDepth = highlightDepth
        Task.detached { LayoutPersistence.save(snapshot) }
    }

    // MARK: - Input

    @ViewBuilder
    private func inputOverlay(geo: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    let hit = nodeAt(screenPoint: loc, size: geo.size)
                    if hit != hoveredNodeID { hoveredNodeID = hit }
                case .ended:
                    if hoveredNodeID != nil { hoveredNodeID = nil }
                }
            }
            // Pinch wins when two fingers are detected; the drag
            // gesture below handles single-finger pan / node drag.
            .highPriorityGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let factor = value / lastMagnification
                        lastMagnification = value
                        cameraAnimTask?.cancel()
                        camera.scale = max(minCameraScale, min(maxCameraScale, camera.scale * factor))
                        bridge.needsDisplay()
                    }
                    .onEnded { _ in
                        lastMagnification = 1
                    }
            )
            // `minimumDistance: 10` so the drag doesn't engage on
            // finger jitter during a long-press hold (the radial
            // LongPress accepts up to 8pt of movement).
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        handleDragChanged(value, size: geo.size)
                    }
                    .onEnded { value in
                        handleDragEnded(value, size: geo.size)
                    }
            )
            .onTapGesture { location in
                handleTap(at: location, size: geo.size)
            }
            // Long-press → radial menus. Press location captured via
            // a simultaneous zero-distance drag because
            // `LongPressGesture` alone doesn't expose its location.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55, maximumDistance: 8)
                    .simultaneously(with: DragGesture(minimumDistance: 0,
                                                     coordinateSpace: .local))
                    .onEnded { value in
                        guard value.first == true,
                              let drag = value.second else { return }
                        if let nodeID = nodeAt(screenPoint: drag.startLocation,
                                               size: geo.size) {
                            Haptics.tap(.medium)
                            onLongPressNode?(nodeID, drag.startLocation)
                            return
                        }
                        let world = GraphProjection(camera: camera, viewSize: geo.size)
                            .worldPoint(screen: drag.startLocation)
                        Haptics.tap(.soft)
                        onLongPressEmptyWorld?(world, drag.startLocation)
                    }
            )
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        // While Connect mode is armed, suppress node drag / pan —
        // the rubber-band overlay handles the visual and the commit
        // fires on .onEnded.
        if connectingFromID != nil { return }
        if draggingNodeID == nil && !isPanningCanvas {
            if let hit = nodeAt(screenPoint: value.startLocation, size: size) {
                #if os(macOS)
                // Shift+drag from a node arms Connect mode — the
                // macOS power-user accelerator for the spatial
                // wire-up.
                if NSEvent.modifierFlags.contains(.shift) {
                    connectingFromID = hit
                    selectedNodeID = hit
                    return
                }
                #endif
                draggingNodeID = hit
                selectedNodeID = hit
                nodeDragStartWorld = store.nodePositions[hit]
            } else {
                isPanningCanvas = true
            }
        }
        if let id = draggingNodeID, let start = nodeDragStartWorld {
            // Translate by the drag delta in world coords —
            // parallax-correct: the node's screen position changes
            // by exactly `value.translation`, no jump.
            let dragged = CGPoint(
                x: start.x + value.translation.width / camera.scale,
                y: start.y + value.translation.height / camera.scale
            )
            store.nodePositions[id] = dragged
            rebuildRenderables()
        } else if isPanningCanvas {
            let delta = CGSize(
                width: value.translation.width - lastPanTranslation.width,
                height: value.translation.height - lastPanTranslation.height)
            lastPanTranslation = value.translation
            cameraAnimTask?.cancel()
            camera.tx += delta.width
            camera.ty += delta.height
            bridge.needsDisplay()
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, size: CGSize) {
        // Connect mode commits at the drop point — covers both the
        // shift+drag path and the radial-armed path where the user
        // dragged rather than tapped.
        if connectingFromID != nil {
            commitConnect(at: value.location, size: size)
            lastPanTranslation = .zero
            return
        }
        if draggingNodeID != nil {
            draggingNodeID = nil
            nodeDragStartWorld = nil
            persistLayout()
        }
        isPanningCanvas = false
        lastPanTranslation = .zero
    }

    private func handleTap(at point: CGPoint, size: CGSize) {
        // Connect mode intercepts taps before selection.
        if connectingFromID != nil {
            commitConnect(at: point, size: size)
            return
        }
        if let hit = nodeAt(screenPoint: point, size: size) {
            selectedNodeID = hit
            return
        }
        // Sticky-selection: a tap within the visible halo of the
        // selected node reaffirms focus rather than throwing it away.
        if let id = selectedNodeID,
           isTapInsideSelectionHalo(at: point, of: id, size: size) {
            return
        }
        selectedNodeID = nil
    }

    /// Commit a Connect-mode action at `endPoint` — tap target,
    /// shift+drag release, etc. Mirrors the Canvas path's
    /// `commitConnect`.
    private func commitConnect(at endPoint: CGPoint, size: CGSize) {
        guard let sourceID = connectingFromID else { return }
        if let target = nodeAt(screenPoint: endPoint, size: size) {
            if target == sourceID {
                connectingFromID = nil
                return
            }
            if let err = store.createEdge(from: sourceID, to: target) {
                store.loadStatus = err
                Haptics.tap(.medium)
                // Keep connect mode armed so the user can re-target.
                return
            }
            if let t = store.graph.nodes[target] {
                store.loadStatus = "Linked → \(t.label)"
            }
            Haptics.tap(.medium)
            connectingFromID = nil
            return
        }
        let world = GraphProjection(camera: camera, viewSize: size)
            .worldPoint(screen: endPoint)
        let cb = onConnectDropEmpty
        let sid = sourceID
        connectingFromID = nil
        cb?(sid, world)
    }

    /// Connect-mode rubber band overlay — gold line from the armed
    /// source to the hovered candidate, with halo rings on both ends.
    @ViewBuilder
    private func connectRubberBand(projection: GraphProjection) -> some View {
        if let sourceID = connectingFromID,
           let srcScreen = screenPosition(for: sourceID, projection: projection) {
            ZStack(alignment: .topLeading) {
                Circle()
                    .stroke(Self.selectionGold.opacity(0.55), lineWidth: 2)
                    .frame(width: 38, height: 38)
                    .position(srcScreen)

                if let targetID = hoveredNodeID,
                   targetID != sourceID,
                   let tgtScreen = screenPosition(for: targetID, projection: projection) {
                    Path { path in
                        path.move(to: srcScreen)
                        path.addLine(to: tgtScreen)
                    }
                    .stroke(Self.selectionGold.opacity(0.75),
                            style: StrokeStyle(lineWidth: 2.5,
                                               lineCap: .round,
                                               dash: [6, 4]))
                    Circle()
                        .stroke(Self.selectionGold.opacity(0.85), lineWidth: 2.5)
                        .frame(width: 42, height: 42)
                        .position(tgtScreen)
                }
            }
            .animation(.easeOut(duration: 0.15), value: hoveredNodeID)
        }
    }

    /// Screen-space center of `nodeID` for overlay drawing — the
    /// parallax-aware projection, sans the per-frame drift wobble.
    private func screenPosition(for nodeID: String,
                                projection: GraphProjection) -> CGPoint? {
        guard let p = store.nodePositions[nodeID],
              let node = store.graph.nodes[nodeID] else { return nil }
        return projection.screenPoint(world: p,
                                      depth: node.depth(in: store.config))
    }

    private func isTapInsideSelectionHalo(at screenPoint: CGPoint,
                                          of nodeID: String,
                                          size: CGSize) -> Bool {
        let projection = GraphProjection(camera: camera, viewSize: size)
        guard let node = store.graph.nodes[nodeID],
              let p = store.nodePositions[nodeID] else { return false }
        let depth = node.depth(in: store.config)
        let s = projection.screenPoint(world: p, depth: depth)
        let d = hypot(s.x - screenPoint.x, s.y - screenPoint.y)
        // Visible halo: node radius + orbital-sparks ring (14 pt) +
        // 8 pt of forgiveness.
        let haloRadius = projection.screenRadius(
            worldRadius: nodeWorldRadius(nodeID), depth: depth) + 14 + 8
        return d < haloRadius
    }

    // MARK: - Renderable extraction

    /// Opacity for nodes/edges outside the highlight set when a node
    /// is selected. 1.0 when no selection.
    private let dimOpacity: Float = 0.10

    /// Resolve `(r, g, b, a)` per type spec, cached once per
    /// renderables rebuild. Saves ~130K NSColor allocations on a
    /// 15K-node / 50K-edge graph, which was previously the dominant
    /// per-rebuild CPU cost.
    private func buildColorTable() -> [String: (Float, Float, Float, Float)] {
        var table: [String: (Float, Float, Float, Float)] = [:]
        for spec in store.config.types {
            table[spec.name] = GraphStore.rgba(of: spec.color)
        }
        return table
    }
    private static let defaultNodeColor: (Float, Float, Float, Float) = (0.85, 0.85, 0.85, 1.0)

    /// Stable 0..1 hash seed derived from a node id. Used by the
    /// Metal shader's drift wobble so every node has unique
    /// phase/frequency on the 2-harmonic offset. Stable across
    /// launches because Swift `String.hashValue` is deterministic
    /// within a process — the visual effect is fine even when it
    /// re-randomizes between launches.
    static func hashSeed(for id: String) -> Float {
        let bucket = UInt32(truncatingIfNeeded: id.hashValue) & 0xFFFF
        return Float(bucket) / Float(0xFFFF)
    }

    /// World-space node radius (degree-coupled, depth cue NOT yet
    /// applied) from the cached adjacency — same min/max/sqrt curve
    /// as the Canvas path, without an O(E) walk per node.
    private func nodeWorldRadius(_ id: String) -> CGFloat {
        let degree = adjacency[id]?.count ?? 0
        // Wider 5–64 band (was 10–28) with a steeper factor so hubs
        // visibly dominate leaves. Kept in lockstep with the Canvas
        // path's minNodeRadius / degreeRadiusFactor / maxNodeRadius.
        let base = 5.0 + 5.0 * sqrt(Double(degree))
        return CGFloat(min(base, 64.0))
    }

    /// N-hop BFS neighborhood of the selection. Empty set when
    /// nothing is selected.
    private func highlightedNodeIDs() -> Set<String> {
        guard let seed = selectedNodeID else { return [] }
        var visited: Set<String> = [seed]
        var frontier: [String] = [seed]
        for _ in 0..<highlightDepth {
            var next: [String] = []
            for node in frontier {
                for neighbor in adjacency[node] ?? [] where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    next.append(neighbor)
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return visited
    }

    private func nodeRenderables() -> [GraphRenderer.NodeRenderable] {
        let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
            Set(store.graph.nodes.values.filter(filter).map(\.id))
        }
        let colorTable = buildColorTable()
        let hasSelection = selectedNodeID != nil
        var out: [GraphRenderer.NodeRenderable] = []
        out.reserveCapacity(store.graph.nodes.count)
        // Walk in depth order (oldest era first) so the GPU draws
        // past-behind-present — instances render in buffer order.
        for node in depthOrderedNodes {
            if let visibleSet, !visibleSet.contains(node.id) { continue }
            guard let pos = store.nodePositions[node.id] else { continue }
            let depth = node.depth(in: store.config)
            let inHighlight = !hasSelection || highlightSet.contains(node.id)
            // Depth cue: older eras shrink, lose opacity, AND lose
            // saturation — same constants as the Canvas path.
            let radius = Float(nodeWorldRadius(node.id)
                * GraphProjection.depthSizeMultiplier(depth: depth))
            let (tr, tg, tb, ta) = colorTable[node.type ?? ""] ?? Self.defaultNodeColor
            let desaturation = Float(1.0 - depth) * 0.55
            let (r, g, b) = desaturatedRGB((tr, tg, tb), by: desaturation)
            let opacity = (inHighlight ? 1.0 : dimOpacity)
                * Float(0.55 + 0.45 * depth) * ta
            let seed = Self.hashSeed(for: node.id)
            out.append(GraphRenderer.NodeRenderable(
                x: Float(pos.x), y: Float(pos.y),
                radius: radius, hashSeed: seed,
                r: r, g: g, b: b, a: opacity,
                depth: Float(depth),
                lightFill: inHighlight ? 1 : 0))
        }
        return out
    }

    private func edgeRenderables() -> [GraphRenderer.EdgeRenderable] {
        let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
            Set(store.graph.nodes.values.filter(filter).map(\.id))
        }
        let colorTable = buildColorTable()
        let hasSelection = selectedNodeID != nil
        var dim: [GraphRenderer.EdgeRenderable] = []
        var bright: [GraphRenderer.EdgeRenderable] = []
        bright.reserveCapacity(store.graph.edges.count)
        let edgeAlpha: Float = 0.50
        for edge in store.graph.edges {
            if let visibleSet,
               !(visibleSet.contains(edge.sourceID) && visibleSet.contains(edge.targetID)) {
                continue
            }
            guard let src = store.graph.nodes[edge.sourceID],
                  let dst = store.graph.nodes[edge.targetID],
                  let p0 = store.nodePositions[edge.sourceID],
                  let p1 = store.nodePositions[edge.targetID] else { continue }
            let dA = src.depth(in: store.config)
            let dB = dst.depth(in: store.config)
            let srcIn = !hasSelection || highlightSet.contains(edge.sourceID)
            let dstIn = !hasSelection || highlightSet.contains(edge.targetID)
            // Per-endpoint opacity / desaturation mirror the Canvas
            // path's `EdgeStrokeRecipe` — each endpoint carries the
            // rendered opacity of the node it connects to, and the
            // edge-wide alpha scales the whole stroke.
            let (sr, sg, sb, _) = colorTable[src.type ?? ""] ?? Self.defaultNodeColor
            let (tr, tg, tb, _) = colorTable[dst.type ?? ""] ?? Self.defaultNodeColor
            let (r0, g0, b0) = desaturatedRGB((sr, sg, sb), by: Float(1.0 - dA) * 0.55)
            let (r1, g1, b1) = desaturatedRGB((tr, tg, tb), by: Float(1.0 - dB) * 0.55)
            let a0 = edgeAlpha * (srcIn ? 1.0 : dimOpacity) * Float(0.55 + 0.45 * dA)
            let a1 = edgeAlpha * (dstIn ? 1.0 : dimOpacity) * Float(0.55 + 0.45 * dB)
            // Stable per-edge bend direction from the id hash — same
            // rule as the Canvas path, so reciprocal A→B / B→A edges
            // curve to opposite sides.
            let curveSign: Float = (abs(edge.id.hashValue) & 1) == 0 ? 1 : -1
            let renderable = GraphRenderer.EdgeRenderable(
                x0: Float(p0.x), y0: Float(p0.y),
                seed0: Self.hashSeed(for: edge.sourceID), depth0: Float(dA),
                r0: r0, g0: g0, b0: b0, a0: a0,
                x1: Float(p1.x), y1: Float(p1.y),
                seed1: Self.hashSeed(for: edge.targetID), depth1: Float(dB),
                r1: r1, g1: g1, b1: b1, a1: a1,
                curveSign: curveSign)
            // Dim edges first in the buffer so highlight-subnet
            // edges overdraw them — same two-pass z-order as the
            // Canvas path.
            if !hasSelection || (srcIn && dstIn) {
                bright.append(renderable)
            } else {
                dim.append(renderable)
            }
        }
        return dim + bright
    }

    // MARK: - Hit testing (screen space, front-to-back)

    /// Hit-test a screen point and return the topmost visible node
    /// under it — respecting per-node radius, zoom coupling, depth
    /// parallax, label pills, and the highlight filter (dimmed
    /// nodes aren't tappable while a selection is active, EXCEPT in
    /// Connect mode where every node is a valid target).
    private func nodeAt(screenPoint: CGPoint, size: CGSize) -> String? {
        let projection = GraphProjection(camera: camera, viewSize: size)
        let slack: CGFloat = 4
        let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
            Set(store.graph.nodes.values.filter(filter).map(\.id))
        }
        let highlightFilter: Set<String>? = {
            if connectingFromID != nil { return nil }
            guard selectedNodeID != nil else { return nil }
            return highlightedNodeIDs()
        }()
        // Walk strictly front-to-back — the first node whose visual
        // disk OR label pill contains the tap wins, matching the
        // render z-order.
        for node in depthOrderedNodes.reversed() {
            let id = node.id
            if let visibleSet, !visibleSet.contains(id) { continue }
            if let highlightFilter, !highlightFilter.contains(id) { continue }
            guard let p = store.nodePositions[id] else { continue }
            let depth = node.depth(in: store.config)
            let s = projection.screenPoint(world: p, depth: depth)
            let d = hypot(s.x - screenPoint.x, s.y - screenPoint.y)
            let tapRadius = projection.screenRadius(
                worldRadius: nodeWorldRadius(id), depth: depth) + slack
            if d < tapRadius {
                return id
            }
            if estimatedLabelRect(for: node, centeredAt: s).contains(screenPoint) {
                return id
            }
        }
        return nil
    }

    /// Conservative bounding rect for a node's drawn label pill,
    /// centered on the node's screen position — labels are what the
    /// user sees and aims at, so they're tappable.
    private func estimatedLabelRect(for node: Node,
                                    centeredAt center: CGPoint) -> CGRect {
        let estFontSize: CGFloat = 12
        let glyphW: CGFloat = estFontSize * 0.62
        let textWidth = CGFloat(node.label.count) * glyphW
        let textHeight = estFontSize * 1.25
        let padH: CGFloat = 8
        let padV: CGFloat = 6
        return CGRect(
            x: center.x - textWidth / 2 - padH,
            y: center.y - textHeight / 2 - padV,
            width: textWidth + padH * 2,
            height: textHeight + padV * 2
        )
    }

    // MARK: - Context menu (macOS right-click)

    #if os(macOS)
    @ViewBuilder
    private func selectedNodeMenu() -> some View {
        if let node = selectedNodeID.flatMap({ store.graph.nodes[$0] }) {
            Text(node.label)
            Button("Open note") { openSelectedNote(node) }
                .disabled(noteURL(for: node) == nil)
            Divider()
            Button("Clear selection") { selectedNodeID = nil }
        } else {
            Text("No node selected")
        }
    }

    private func noteURL(for node: Node) -> URL? {
        if let path = node.filePath { return URL(fileURLWithPath: path) }
        return node.file
    }

    private func openSelectedNote(_ node: Node) {
        if let url = noteURL(for: node) {
            _ = openFileURL(url)
        }
    }
    #endif
}

// MARK: - Deterministic RNG for the atmosphere speck field

/// Tiny seeded RNG so the background star-field is identical every
/// launch — and identical to the Canvas path's field (same seed +
/// constants as `GraphCanvasView.seedAtmosphereSpecks`).
private struct SplitMix64Speck {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Returns a Double in `[0, 1)`.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// MARK: - FPS overlay

/// Isolated observer of `bridge.fps` so the readout updates twice
/// per second WITHOUT invalidating `GraphMetalView.body` — the
/// parent body owns the 15K-node renderable rebuild and we don't
/// want an fps tick to trigger a full extraction + GPU upload.
struct FPSOverlay: View {
    @ObservedObject var bridge: MetalBridge

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text(String(format: "%.0f fps", bridge.fps))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(fpsColor(bridge.fps))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 60 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }
}

// MARK: - Bridge / Container

/// Holds a reference to the active MTKView so SwiftUI gesture
/// handlers can call `setNeedsDisplay()` without going through the
/// representable's `updateUIView/updateNSView` pathway (which would
/// re-evaluate the whole body just to mark a frame dirty).
@MainActor
final class MetalBridge: ObservableObject {
    weak var metalView: MTKView?
    /// True if `GraphRenderer.init?` returned nil. Surfaced as a
    /// visible red overlay so init failures aren't invisible white
    /// screens — the prior behavior on this code path.
    @Published var rendererFailed: Bool = false
    /// Rolling FPS sampled by the renderer at ~2× per second. 0
    /// while no draws have completed yet (first ~half second).
    @Published var fps: Double = 0
    func needsDisplay() {
        guard let metalView else { return }
        #if canImport(AppKit)
        metalView.needsDisplay = true
        #else
        metalView.setNeedsDisplay()
        #endif
    }
}

/// `_ViewRepresentable` wrapper that owns the `MTKView` + the
/// `GraphRenderer`. Re-uploads geometry only when the revision
/// counters move — keeps pan/pinch from re-uploading 15K nodes per
/// gesture tick.
struct MetalContainer: _ViewRepresentable {
    @ObservedObject var bridge: MetalBridge
    var camera: GraphRenderer.Camera
    var nodes: [GraphRenderer.NodeRenderable]
    var edges: [GraphRenderer.EdgeRenderable]
    var specks: [GraphRenderer.SpeckRenderable]
    /// Monotonic counter the parent bumps when `nodes` / `edges`
    /// change.
    var dataRevision: Int
    /// Monotonic counter for the (rarely-changing) speck field.
    var speckRevision: Int

    final class Coordinator {
        var renderer: GraphRenderer?
        var lastUploadedRevision: Int = -1
        var lastSpeckRevision: Int = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if canImport(AppKit)
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        if let renderer = GraphRenderer(mtkView: view) {
            renderer.fpsCallback = { [weak bridge] fps in
                bridge?.fps = fps
            }
            context.coordinator.renderer = renderer
            bridge.rendererFailed = false
        } else {
            bridge.rendererFailed = true
        }
        bridge.metalView = view
        return view
    }
    func updateNSView(_ nsView: MTKView, context: Context) {
        applyUpdate(view: nsView, context: context)
    }
    #endif
    #if canImport(UIKit)
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.isOpaque = false
        view.backgroundColor = .clear
        if let renderer = GraphRenderer(mtkView: view) {
            renderer.fpsCallback = { [weak bridge] fps in
                bridge?.fps = fps
            }
            context.coordinator.renderer = renderer
            bridge.rendererFailed = false
        } else {
            bridge.rendererFailed = true
        }
        bridge.metalView = view
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {
        applyUpdate(view: uiView, context: context)
    }
    #endif

    private func applyUpdate(view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.camera = camera
        if context.coordinator.lastUploadedRevision != dataRevision {
            renderer.update(nodes: nodes, edges: edges)
            context.coordinator.lastUploadedRevision = dataRevision
        }
        if context.coordinator.lastSpeckRevision != speckRevision {
            renderer.updateSpecks(specks)
            context.coordinator.lastSpeckRevision = speckRevision
        }
        #if canImport(AppKit)
        view.needsDisplay = true
        #else
        view.setNeedsDisplay()
        #endif
    }
}
