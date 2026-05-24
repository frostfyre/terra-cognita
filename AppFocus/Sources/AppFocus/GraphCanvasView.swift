import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct GraphCanvasView: View {
    @ObservedObject var store: GraphStore

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScaleValue: CGFloat = 1
    @State private var canvasSize: CGSize = .zero

    /// Per-node manually-pinned positions in world space. Pinned nodes
    /// are not displaced by future automatic layouts.
    @State private var pinnedPositions: [String: CGPoint] = [:]
    /// While the user is dragging a node, this holds its id.
    @State private var draggingNodeID: String?

    /// When nothing is selected, the canvas periodically "puffs" a random
    /// node so the graph feels alive and the eye gets surfaced to nodes
    /// it might not otherwise notice.
    @State private var ambientHighlightID: String?
    @State private var ambientHighlightStart: TimeInterval?
    private let ambientPuffDuration: Double = 2.4
    /// Owned by `GraphView` so the inspector panel can drive it too.
    @Binding var selectedNodeID: String?
    /// Optional node-visibility filter (lens). `nil` means show everything.
    /// Edges are visible only when both endpoints pass the filter.
    var visibleNodeFilter: ((Node) -> Bool)? = nil
    /// Wall-clock time of the most recent selection. Drives the
    /// "selected node briefly doubles in size" pulse.
    @State private var selectionPulseStart: TimeInterval?

    private let selectionPulseDuration: Double = 0.4

    /// Cached node positions in world space. Rewritten when the graph
    /// changes (first to a circular seed, then to a force-directed layout
    /// once the background computation finishes).
    @State private var layout: [String: CGPoint] = [:]
    @State private var layoutKind: LayoutKind = .none

    /// Undirected adjacency, rebuilt when the graph changes. Used for the
    /// "dim everything outside the N-hop neighborhood of the selection".
    @State private var adjacency: [String: [String]] = [:]

    /// Nodes sorted back-to-front by depth (oldest era first). Rebuilt
    /// when the graph changes so we don't pay for an O(n log n) sort on
    /// every Canvas redraw.
    @State private var depthOrderedNodes: [Node] = []

    /// Deep-background specks (a sparse star-field) seeded once on
    /// appear. They drift in world space with the maximum parallax so
    /// they appear "behind" everything when the user pans.
    @State private var atmosphereSpecks: [AtmosphereSpeck] = []

    private struct AtmosphereSpeck {
        var x: CGFloat       // world x
        var y: CGFloat       // world y
        var radius: CGFloat  // 0.6 – 1.6 px
        var phase: Double    // twinkle phase
    }

    private enum LayoutKind { case none, circular, forceDirected }

    /// How many BFS hops from the selected node remain at full opacity.
    private let highlightDepth = 1

    /// Opacity for nodes/edges outside the highlight set when a node is
    /// selected. 1.0 when no selection.
    private let dimOpacity: Double = 0.10

    /// Edges grouped by stroke color so the Canvas can issue one stroke
    /// per group instead of per edge.
    private struct EdgeGroup {
        let color: Color
        let path: Path
    }

    var body: some View {
        GeometryReader { geo in
            let highlight = highlightedNodeIDs()
            let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
                Set(store.graph.nodes.values.filter(filter).map(\.id))
            }

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                // Subtract a baseline so `t` stays a small positive double
                // (timeIntervalSinceReferenceDate is currently ~8e8 — fine
                // for sin precision but a bit absurd to multiply by).
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 86400)

                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let s = scale
                    let off = offset

                    // Ambient drift — sea-anemone style: each node has its
                    // own *frequency* per axis (not just phase), derived
                    // from hash bits, so the field looks fully independent.
                    // Angular velocities live in the 1–3 rad/sec range
                    // (period ~2-6s) and amplitudes are in screen pixels.
                    func driftFor(_ id: String) -> CGPoint {
                        let h = id.hashValue
                        let pa = Double(h & 0xFF) / 255.0 * 6.28318
                        let pb = Double((h >> 8) & 0xFF) / 255.0 * 6.28318
                        let pc = Double((h >> 16) & 0xFF) / 255.0 * 6.28318
                        let pd = Double((h >> 24) & 0xFF) / 255.0 * 6.28318
                        // Frequencies: 1.0–2.5 and 1.4–2.9 rad/sec.
                        let fa = 1.0 + Double((h >> 32) & 0xFF) / 255.0 * 1.5
                        let fb = 1.4 + Double((h >> 40) & 0xFF) / 255.0 * 1.5
                        let fc = 1.0 + Double((h >> 48) & 0xFF) / 255.0 * 1.5
                        let fd = 1.4 + Double((h >> 56) & 0xFF) / 255.0 * 1.5
                        let x = sin(t * fa + pa) * 8.0 + sin(t * fb + pb) * 4.0
                        let y = cos(t * fc + pc) * 8.0 + cos(t * fd + pd) * 4.0
                        return CGPoint(x: x, y: y)
                    }

                    /// Parallax factor for a node at depth `d` (0 = deep, 1 = front).
                    /// Foreground tracks pan 1:1, deepest layer at ~55%.
                    func parallax(_ d: Double) -> CGFloat {
                        CGFloat(0.55 + 0.45 * d)
                    }

                    /// Project a world point to screen coordinates with
                    /// parallax (depth-aware offset) and ambient drift.
                    func toScreen(_ id: String, _ p: CGPoint, _ d: Double) -> CGPoint {
                        let drift = driftFor(id)
                        let pf = parallax(d)
                        return CGPoint(x: center.x + p.x * s + off.width * pf + drift.x,
                                       y: center.y + p.y * s + off.height * pf + drift.y)
                    }

                    let hasSelection = selectedNodeID != nil

                    // --- Atmospheric background ---
                    // A radial vignette from a subtle indigo centre to a
                    // darker edge, so the canvas reads as a volume rather
                    // than a flat sheet.
                    let bgRect = CGRect(origin: .zero, size: size)
                    context.fill(
                        Path(bgRect),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 0.10, green: 0.11, blue: 0.18).opacity(0.55),
                                Color(red: 0.03, green: 0.03, blue: 0.06).opacity(0.85)
                            ]),
                            center: center,
                            startRadius: 0,
                            endRadius: max(size.width, size.height) * 0.7
                        )
                    )
                    // Deep specks — a sparse star-field at the back of the
                    // depth axis, with maximum parallax. Provides motion
                    // parallax against the moving graph.
                    let speckParallax = parallax(0)
                    for speck in atmosphereSpecks {
                        let sx = center.x + speck.x * s + off.width * speckParallax
                        let sy = center.y + speck.y * s + off.height * speckParallax
                        // Subtle twinkle keyed off the speck's own offset.
                        let twinkle = 0.45 + 0.4 * sin(t * 0.6 + speck.phase)
                        let r = CGFloat(speck.radius)
                        let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(.white.opacity(twinkle * 0.45)))
                    }

                    // Edges — dim layer first, bright on top.
                    let groups = edgeGroups(toScreen: toScreen,
                                            highlight: highlight,
                                            hasSelection: hasSelection,
                                            visibleSet: visibleSet)
                    for group in groups.dim {
                        context.stroke(group.path,
                                       with: .color(group.color.opacity(dimOpacity * 0.6)),
                                       lineWidth: 1)
                    }
                    for group in groups.bright {
                        context.stroke(group.path,
                                       with: .color(group.color.opacity(0.7)),
                                       lineWidth: 1.2)
                    }

                    // Nodes — radius scales with degree (min 10, sqrt curve so
                    // hub nodes are clearly bigger without dwarfing leaves).
                    // Label visibility raised so labels only render once
                    // there's room (avoids the dense mass-of-text look).
                    let labelEnabled = s > 0.85
                    let selectionPulse: CGFloat = {
                        guard let start = selectionPulseStart else { return 0 }
                        let elapsed = t - start
                        guard elapsed >= 0, elapsed <= selectionPulseDuration else { return 0 }
                        let phase = elapsed / selectionPulseDuration
                        return CGFloat(sin(.pi * phase))
                    }()

                    // Idle-state ambient puff — only fires when nothing is
                    // selected. A sin curve scales the node radius up then
                    // back down over `ambientPuffDuration` seconds.
                    let ambientPuff: CGFloat = {
                        guard !hasSelection,
                              ambientHighlightID != nil,
                              let start = ambientHighlightStart else { return 0 }
                        let elapsed = t - start
                        guard elapsed >= 0, elapsed <= ambientPuffDuration else { return 0 }
                        let phase = elapsed / ambientPuffDuration
                        return CGFloat(sin(.pi * phase))
                    }()

                    // Defer the selected and currently-puffed nodes so they
                    // draw on top of everything else.
                    var deferredSelected: (Node, CGPoint, CGFloat)?
                    var deferredAmbient: (Node, CGPoint, CGFloat)?

                    // First pass — all non-deferred nodes, walked in
                    // depth order so the most "present" nodes overdraw
                    // older ones (DESIGN.md's "time as depth" idea).
                    for node in depthOrderedNodes {
                        if let visibleSet, !visibleSet.contains(node.id) { continue }
                        guard let worldPoint = effectivePosition(for: node.id) else { continue }
                        let depth = node.depth
                        let p = toScreen(node.id, worldPoint, depth)
                        let isSelected = selectedNodeID == node.id
                        let isAmbient = !hasSelection
                            && ambientHighlightID == node.id
                            && ambientPuff > 0.01
                        let baseRadius = radiusFor(nodeID: node.id)

                        if isSelected {
                            deferredSelected = (node, p, baseRadius)
                            continue
                        }
                        if isAmbient {
                            deferredAmbient = (node, p, baseRadius)
                            continue
                        }

                        let inHighlight = !hasSelection || highlight.contains(node.id)
                        // Depth cue: nodes from older eras shrink slightly and
                        // lose a touch of opacity, so the foreground stays
                        // visually dominant without losing background context.
                        let depthSizeMul = 0.85 + 0.35 * CGFloat(depth)
                        let depthOpacityMul = 0.55 + 0.45 * depth
                        let drawRadius = baseRadius * depthSizeMul
                        let opacity = (inHighlight ? 1.0 : dimOpacity) * depthOpacityMul
                        let fill = nodeColor(node).opacity(opacity)
                        let rect = CGRect(x: p.x - drawRadius, y: p.y - drawRadius,
                                          width: drawRadius * 2, height: drawRadius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(fill))

                        // Pinned indicator — small white outline so the pin
                        // status is legible at a glance.
                        if pinnedPositions[node.id] != nil {
                            context.stroke(Path(ellipseIn: rect),
                                           with: .color(.white.opacity(inHighlight ? 0.95 : dimOpacity)),
                                           lineWidth: 1.5)
                        }

                        // Labels for background-pass nodes: only when
                        // zoomed in or part of an active highlight set.
                        let showLabel = inHighlight && (labelEnabled || hasSelection)
                        if showLabel {
                            let resolved = context.resolve(
                                Text(node.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.primary.opacity(depthOpacityMul))
                            )
                            context.draw(resolved, at: p, anchor: .center)
                        }
                    }

                    // Foreground pass — the idle-puffed node, drawn above
                    // every other background node so the spotlight reads.
                    if let (node, p, baseRadius) = deferredAmbient {
                        let drawRadius = baseRadius * (1 + ambientPuff * 0.9)
                        let fill = nodeColor(node)
                        let rect = CGRect(x: p.x - drawRadius, y: p.y - drawRadius,
                                          width: drawRadius * 2, height: drawRadius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(fill))

                        if pinnedPositions[node.id] != nil {
                            context.stroke(Path(ellipseIn: rect),
                                           with: .color(.white),
                                           lineWidth: 1.5)
                        }

                        let r = drawRadius + 2 + ambientPuff * 2
                        let ring = CGRect(x: p.x - r, y: p.y - r,
                                          width: r * 2, height: r * 2)
                        context.stroke(Path(ellipseIn: ring),
                                       with: .color(.accentColor.opacity(0.55 * ambientPuff)),
                                       lineWidth: 1.5)

                        let fontSize: CGFloat = 10 + ambientPuff * 3
                        let resolved = context.resolve(
                            Text(node.label)
                                .font(.system(size: fontSize).weight(.medium))
                                .foregroundStyle(.primary)
                        )
                        context.draw(resolved, at: p, anchor: .center)
                    }

                    // Second pass — the selected node, drawn last so it sits
                    // on top of every edge, neighbor, and label.
                    if let (node, p, baseRadius) = deferredSelected {
                        let nodeRadius = baseRadius * (1 + selectionPulse)
                        let fill = nodeColor(node)
                        let rect = CGRect(x: p.x - nodeRadius, y: p.y - nodeRadius,
                                          width: nodeRadius * 2, height: nodeRadius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(fill))

                        let r: CGFloat = nodeRadius + 3
                        let ring = CGRect(x: p.x - r, y: p.y - r,
                                          width: r * 2, height: r * 2)
                        context.stroke(Path(ellipseIn: ring),
                                       with: .color(.accentColor), lineWidth: 2)

                        // Selected label is always visible and centred on
                        // the node so the focus point reads at any scale.
                        let labelScale: CGFloat = 1 + selectionPulse
                        let resolved = context.resolve(
                            Text(node.label)
                                .font(.system(size: 11 * labelScale).weight(.semibold))
                                .foregroundStyle(.primary)
                        )
                        context.draw(resolved, at: p, anchor: .center)
                    }
                }
            }
            .contentShape(Rectangle())
            .background(
                MouseInputMonitor(
                    onScroll: { delta in
                        let factor = 1.0 + (delta * 0.0035)
                        let newScale = scale * factor
                        scale = max(0.25, min(4.0, newScale))
                    },
                    onMiddleDrag: { dx, dy in
                        offset = CGSize(width: offset.width + dx,
                                        height: offset.height + dy)
                    }
                )
            )
            .gesture(pinchGesture())
            .gesture(nodeDragGesture(size: geo.size))
            .onTapGesture(coordinateSpace: .local) { point in
                handleTap(at: point, size: geo.size)
            }
            .contextMenu { selectedNodeMenu() }
            .onAppear {
                canvasSize = geo.size
                seedAtmosphereSpecks()
            }
            .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
        }
        .task(id: store.graph.nodes.count) {
            await rebuildLayoutPipeline()
        }
        .task { await runAmbientCycle() }
        .onChange(of: selectedNodeID) { _, newValue in
            if newValue != nil {
                // Match the time domain used inside the Canvas closure
                // (timeline.date mod 86400) so `elapsed = t - start` is sane.
                selectionPulseStart = Date().timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 86400)
                frameHighlightedSubnet()
                // Cancel any in-flight ambient puff so it doesn't fight
                // the user's deliberate selection.
                ambientHighlightID = nil
                ambientHighlightStart = nil
            }
        }
    }

    // MARK: - Idle / ambient animation

    /// Background loop that periodically picks a random node and puffs it
    /// when the user is idle (no selection). One puff at a time, spaced
    /// 3.5–6.5 seconds apart. Sleeps quietly during user interaction.
    private func runAmbientCycle() async {
        // Small initial delay so the first puff doesn't fire while the
        // layout is still settling.
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            let pause = Double.random(in: 3.5...6.5)
            try? await Task.sleep(for: .seconds(pause))
            if Task.isCancelled { break }

            // Only act when the user is idle and we have nodes to choose from.
            guard selectedNodeID == nil, !store.graph.nodes.isEmpty else { continue }

            // Pick a node, weighted toward higher-degree (more interesting)
            // nodes so the spotlight surfaces meaningful entries more often.
            let nodes = Array(store.graph.nodes.values)
            let chosen = pickWeightedNode(from: nodes) ?? nodes.randomElement()
            guard let id = chosen?.id, id != ambientHighlightID else { continue }

            ambientHighlightID = id
            ambientHighlightStart = Date().timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 86400)
        }
    }

    /// Generate a deterministic field of background specks once so they
    /// don't shimmer between redraws. Scattered across a wide world rect
    /// so panning reveals new specks rather than running out.
    private func seedAtmosphereSpecks() {
        guard atmosphereSpecks.isEmpty else { return }
        var rng = SplitMix64(seed: 0xC0FFEE_CAFE_BEEF)
        let count = 140
        let halfWidth: CGFloat = 4000
        let halfHeight: CGFloat = 3000
        atmosphereSpecks = (0..<count).map { _ in
            AtmosphereSpeck(
                x: CGFloat(rng.nextUnit() * 2 - 1) * halfWidth,
                y: CGFloat(rng.nextUnit() * 2 - 1) * halfHeight,
                radius: 0.6 + CGFloat(rng.nextUnit()) * 1.0,
                phase: rng.nextUnit() * 6.28318
            )
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

    // MARK: - Auto-framing

    /// Animate `scale` and `offset` so the currently highlighted subnet
    /// (selected node + 1-hop neighbors) fits the canvas with padding.
    /// Skipped if the layout or canvas size isn't ready yet.
    private func frameHighlightedSubnet() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let highlighted = highlightedNodeIDs()
        let points = highlighted.compactMap { effectivePosition(for: $0) }
        guard !points.isEmpty else { return }

        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let centerWorld = CGPoint(x: (minX + maxX) / 2,
                                  y: (minY + maxY) / 2)
        // Floor the bbox so a singleton (no neighbors) doesn't try to zoom
        // to infinity, and pad the world rect to make room for node radii
        // and a little breathing space.
        let widthWorld  = max(maxX - minX + 80, 200)
        let heightWorld = max(maxY - minY + 80, 200)

        let chromePadding: CGFloat = 60  // top bar + inspector breathing room
        let availableWidth  = max(canvasSize.width  - chromePadding * 2, 200)
        let availableHeight = max(canvasSize.height - chromePadding * 2, 200)

        let candidate = min(availableWidth / widthWorld,
                            availableHeight / heightWorld)
        // Don't zoom past 2.2× (a singleton would otherwise become huge),
        // and don't zoom out below the user's current setting unless we
        // need to.
        let targetScale = max(0.4, min(candidate, 2.2))

        let targetOffset = CGSize(width: -centerWorld.x * targetScale,
                                  height: -centerWorld.y * targetScale)

        withAnimation(.easeInOut(duration: 0.55)) {
            scale = targetScale
            offset = targetOffset
            lastScaleValue = 1
        }
    }

    // MARK: - Layout pipeline (circular seed → background force-directed)

    private func rebuildLayoutPipeline() async {
        let snapshotNodes = Array(store.graph.nodes.values)
        let nodeIDs = snapshotNodes.map { $0.id }
        let edgePairs = store.graph.edges.map { ($0.sourceID, $0.targetID) }

        rebuildAdjacency()

        guard !nodeIDs.isEmpty else {
            layout = [:]
            return
        }

        // Try to restore a saved layout for the same node set. If every
        // current node has a saved position we skip FA2 entirely — the
        // user's persistent placements stay put across launches.
        if let persisted = LayoutPersistence.load() {
            let saved = persisted.cgPositions
            if Set(nodeIDs).isSubset(of: Set(saved.keys)) {
                layout = saved
                pinnedPositions = persisted.cgPinned
                scale = max(0.25, min(4.0, CGFloat(persisted.scale)))
                offset = CGSize(width: persisted.offsetX, height: persisted.offsetY)
                layoutKind = .forceDirected
                return
            }
        }

        // 1. Cheap circular seed so something appears immediately.
        layout = makeCircularLayout(for: nodeIDs)
        layoutKind = .circular

        // 2. Background force-directed layout, swapped in once it converges.
        let solver = ForceDirectedLayout()
        let computed = await Task.detached(priority: .userInitiated) {
            solver.compute(nodeIDs: nodeIDs, edges: edgePairs)
        }.value

        // Bail if the graph has been replaced under us while we were thinking.
        guard store.graph.nodes.count == nodeIDs.count else { return }

        withAnimation(.easeInOut(duration: 0.6)) {
            layout = computed
            layoutKind = .forceDirected
        }
        persistLayout()
    }

    /// Snapshot current layout + view state and persist to disk.
    private func persistLayout() {
        var snapshot = PersistedLayout()
        snapshot.positions = layout.mapValues(PersistedLayout.Point.init)
        snapshot.pinned = pinnedPositions.mapValues(PersistedLayout.Point.init)
        snapshot.scale = Double(scale)
        snapshot.offsetX = Double(offset.width)
        snapshot.offsetY = Double(offset.height)
        Task.detached { LayoutPersistence.save(snapshot) }
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

    // MARK: - Highlight set (N-hop BFS from the selection)

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

    private func rebuildAdjacency() {
        var adj: [String: [String]] = [:]
        adj.reserveCapacity(store.graph.nodes.count)
        for edge in store.graph.edges {
            adj[edge.sourceID, default: []].append(edge.targetID)
            adj[edge.targetID, default: []].append(edge.sourceID)
        }
        adjacency = adj
        depthOrderedNodes = store.graph.nodes.values
            .sorted { $0.depth < $1.depth }
    }

    // MARK: - Node sizing by degree

    private let minNodeRadius: CGFloat = 10
    private let degreeRadiusFactor: CGFloat = 2.4   // multiplier on sqrt(degree)
    private let maxNodeRadius: CGFloat = 28

    private func radiusFor(nodeID: String) -> CGFloat {
        let degree = adjacency[nodeID]?.count ?? 0
        let scaled = minNodeRadius + degreeRadiusFactor * CGFloat(sqrt(Double(degree)))
        return min(scaled, maxNodeRadius)
    }

    // MARK: - Hit testing

    private func handleTap(at point: CGPoint, size: CGSize) {
        selectedNodeID = nodeAt(screenPoint: point, size: size)
        // Pulse-start is driven by `.onChange(of: selectedNodeID)` so it
        // fires for selections coming from the inspector too.
    }

    // MARK: - Edge batching

    private struct EdgeBatches {
        var dim: [EdgeGroup] = []
        var bright: [EdgeGroup] = []
    }

    private func edgeGroups(toScreen: (String, CGPoint, Double) -> CGPoint,
                            highlight: Set<String>,
                            hasSelection: Bool,
                            visibleSet: Set<String>?) -> EdgeBatches {
        var dimByColor: [String: (Color, Path)] = [:]
        var brightByColor: [String: (Color, Path)] = [:]

        for edge in store.graph.edges {
            if let visibleSet,
               !(visibleSet.contains(edge.sourceID) && visibleSet.contains(edge.targetID)) {
                continue
            }
            guard let a = effectivePosition(for: edge.sourceID),
                  let b = effectivePosition(for: edge.targetID) else { continue }
            let dA = store.graph.nodes[edge.sourceID]?.depth ?? 0.55
            let dB = store.graph.nodes[edge.targetID]?.depth ?? 0.55
            let color = edgeColor(edge)
            let key = colorKey(color)
            let isBright = !hasSelection ||
                (highlight.contains(edge.sourceID) && highlight.contains(edge.targetID))

            if isBright {
                var entry = brightByColor[key] ?? (color, Path())
                entry.1.move(to: toScreen(edge.sourceID, a, dA))
                entry.1.addLine(to: toScreen(edge.targetID, b, dB))
                brightByColor[key] = entry
            } else {
                var entry = dimByColor[key] ?? (color, Path())
                entry.1.move(to: toScreen(edge.sourceID, a, dA))
                entry.1.addLine(to: toScreen(edge.targetID, b, dB))
                dimByColor[key] = entry
            }
        }

        return EdgeBatches(
            dim: dimByColor.values.map { EdgeGroup(color: $0.0, path: $0.1) },
            bright: brightByColor.values.map { EdgeGroup(color: $0.0, path: $0.1) }
        )
    }

    private func colorKey(_ c: Color) -> String { String(describing: c) }

    // MARK: - Gestures

    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScaleValue
                let newScale = scale * delta
                scale = max(0.25, min(4.0, newScale))
                lastScaleValue = value
            }
            .onEnded { _ in
                lastScaleValue = 1
            }
    }

    /// Left-mouse drag = move a node (if drag started on one). Drags on
    /// empty canvas are ignored — middle-mouse pan handles panning.
    private func nodeDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                if draggingNodeID == nil {
                    // First frame of the drag — see if it started on a node.
                    if let hit = nodeAt(screenPoint: value.startLocation, size: size) {
                        draggingNodeID = hit
                        selectedNodeID = hit
                    }
                }
                if let id = draggingNodeID {
                    pinnedPositions[id] = worldPoint(at: value.location, size: size)
                }
            }
            .onEnded { _ in
                draggingNodeID = nil
                persistLayout()
            }
    }

    /// World-space position the canvas should render for a given node.
    /// Pinned positions override the layout dictionary.
    private func effectivePosition(for id: String) -> CGPoint? {
        if let pinned = pinnedPositions[id] { return pinned }
        return layout[id]
    }

    /// Convert a screen-space point inside the canvas to a world-space
    /// coordinate, undoing the current scale/offset/centre transform.
    private func worldPoint(at screen: CGPoint, size: CGSize) -> CGPoint {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: (screen.x - centre.x - offset.width) / scale,
                       y: (screen.y - centre.y - offset.height) / scale)
    }

    /// Hit-test a screen point and return the id of the topmost visible
    /// node under the cursor (respecting per-node radius + zoom-aware
    /// slack + the depth-based parallax offset).
    private func nodeAt(screenPoint: CGPoint, size: CGSize) -> String? {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let slack: CGFloat = 4
        let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
            Set(store.graph.nodes.values.filter(filter).map(\.id))
        }
        // Walk front-to-back so the topmost (most foreground) node wins
        // when several stack near the cursor.
        var bestID: String?
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for node in depthOrderedNodes.reversed() {
            let id = node.id
            if let visibleSet, !visibleSet.contains(id) { continue }
            guard let p = effectivePosition(for: id) else { continue }
            let pf = CGFloat(0.55 + 0.45 * node.depth)
            // Same projection as toScreen, minus the per-frame drift
            // (drift wobble shouldn't disturb hit-testing).
            let sx = centre.x + p.x * scale + offset.width * pf
            let sy = centre.y + p.y * scale + offset.height * pf
            let d = hypot(sx - screenPoint.x, sy - screenPoint.y)
            let tapRadius = radiusFor(nodeID: id) + slack
            if d < tapRadius && d < bestDistance {
                bestDistance = d
                bestID = id
            }
        }
        return bestID
    }

    // MARK: - Styling

    private func edgeColor(_ edge: Edge) -> Color {
        switch edge.provenance {
        case .some(.directInfluence): return .blue
        case .some(.verifiedLineage): return .green
        case .some(.institutionalConnection): return .teal
        case .some(.inferredAffinity): return .purple
        case .some(.recommendation): return .orange
        case .some(.adjacency): return .gray
        case .some(.speculation): return .pink
        case .none: return .secondary
        }
    }

    private func nodeColor(_ node: Node) -> Color {
        switch node.type {
        case "person": return .cyan
        case "concept": return .yellow
        case "institution": return .mint
        case "event": return .orange
        case "work": return .pink
        default: return .white.opacity(0.9)
        }
    }

    // MARK: - Context menu (operates on currently selected node)

    @ViewBuilder
    private func selectedNodeMenu() -> some View {
        if let id = selectedNodeID, let node = store.graph.nodes[id] {
            Text(node.label)
            Button("Open note") { openSelectedNote(node) }
                .disabled(noteURL(for: node) == nil)
            Divider()
            if pinnedPositions[id] != nil {
                Button("Unpin") {
                    pinnedPositions.removeValue(forKey: id)
                    persistLayout()
                }
            } else {
                Button("Pin in place") {
                    if let p = layout[id] { pinnedPositions[id] = p }
                    persistLayout()
                }
            }
            if !pinnedPositions.isEmpty {
                Button("Unpin all (\(pinnedPositions.count))") {
                    pinnedPositions.removeAll()
                    persistLayout()
                }
            }
            Divider()
            Button("Clear selection") { selectedNodeID = nil }
        } else {
            Text("No node selected")
            if !pinnedPositions.isEmpty {
                Button("Unpin all (\(pinnedPositions.count))") {
                    pinnedPositions.removeAll()
                    persistLayout()
                }
            }
        }
    }

    /// Resolve the URL for a node's backing markdown file. `VaultLoader` sets
    /// `filePath` to an absolute path on disk — prefer that over the
    /// bundle-based lookup in `Node+File.swift`, which never resolves because
    /// we don't ship the vault as a bundle resource.
    private func noteURL(for node: Node) -> URL? {
        if let path = node.filePath { return URL(fileURLWithPath: path) }
        return node.file
    }

    private func openSelectedNote(_ node: Node) {
        if let url = noteURL(for: node) {
            _ = openFileURL(url)
        }
    }
}

// MARK: - Deterministic RNG for the atmosphere speck field

/// Tiny seeded RNG so the background star-field is identical every launch.
/// Not cryptographically anything — just stable + cheap.
private struct SplitMix64 {
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

// MARK: - Mouse input monitor (macOS) — scroll wheel + middle-mouse drag

/// Invisible NSView that installs window-scoped `NSEvent` monitors for the
/// scroll wheel and middle-mouse drag. Returns `nil` from `hitTest(_:)` so
/// left-click events still reach SwiftUI underneath.
#if os(macOS)
private struct MouseInputMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onMiddleDrag: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MouseInputView()
        view.onScroll = onScroll
        view.onMiddleDrag = onMiddleDrag
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MouseInputView else { return }
        view.onScroll = onScroll
        view.onMiddleDrag = onMiddleDrag
    }

    private final class MouseInputView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onMiddleDrag: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?
        private var lastDragLocation: NSPoint?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                let mask: NSEvent.EventTypeMask = [
                    .scrollWheel,
                    .otherMouseDown, .otherMouseDragged, .otherMouseUp
                ]
                monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    guard let self,
                          let window = self.window,
                          event.window === window else { return event }
                    let pt = self.convert(event.locationInWindow, from: nil)
                    let inside = self.bounds.contains(pt)

                    switch event.type {
                    case .scrollWheel:
                        guard inside else { return event }
                        let dy = event.hasPreciseScrollingDeltas
                            ? event.scrollingDeltaY
                            : event.scrollingDeltaY * 10
                        self.onScroll?(dy)
                        return nil

                    case .otherMouseDown:
                        guard inside else { return event }
                        self.lastDragLocation = event.locationInWindow
                        return nil

                    case .otherMouseDragged:
                        guard let last = self.lastDragLocation else { return event }
                        let dx = event.locationInWindow.x - last.x
                        let dyWindow = event.locationInWindow.y - last.y
                        // NSWindow has y-up coords; SwiftUI offset uses y-down.
                        self.onMiddleDrag?(dx, -dyWindow)
                        self.lastDragLocation = event.locationInWindow
                        return nil

                    case .otherMouseUp:
                        guard self.lastDragLocation != nil else { return event }
                        self.lastDragLocation = nil
                        return nil

                    default:
                        return event
                    }
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#else
private struct MouseInputMonitor: View {
    let onScroll: (CGFloat) -> Void
    let onMiddleDrag: (CGFloat, CGFloat) -> Void
    var body: some View { Color.clear }
}
#endif
