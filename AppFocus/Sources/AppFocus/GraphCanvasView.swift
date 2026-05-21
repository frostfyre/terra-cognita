import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct GraphCanvasView: View {
    @ObservedObject var store: GraphStore

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScaleValue: CGFloat = 1
    @State private var selectedNodeID: String?

    /// Cached node positions in world space. Rewritten when the graph
    /// changes (first to a circular seed, then to a force-directed layout
    /// once the background computation finishes).
    @State private var layout: [String: CGPoint] = [:]
    @State private var layoutKind: LayoutKind = .none

    /// Undirected adjacency, rebuilt when the graph changes. Used for the
    /// "dim everything outside the N-hop neighborhood of the selection".
    @State private var adjacency: [String: [String]] = [:]

    private enum LayoutKind { case none, circular, forceDirected }

    /// How many BFS hops from the selected node remain at full opacity.
    private let highlightDepth = 2

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

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let s = scale
                    let off = offset

                    // Subtle ambient drift — each node wobbles a couple of
                    // pixels along an irreducible offset derived from its ID.
                    func driftFor(_ id: String) -> CGPoint {
                        let h = Double(id.hashValue & 0xFFFF)
                        let phase = h * 0.0001
                        return CGPoint(
                            x: sin(t * 0.35 + phase * 6.28) * 1.6,
                            y: cos(t * 0.30 + phase * 6.28 + 1.2) * 1.6
                        )
                    }

                    func toScreen(_ id: String, _ p: CGPoint) -> CGPoint {
                        let drift = driftFor(id)
                        let wx = p.x + drift.x
                        let wy = p.y + drift.y
                        return CGPoint(x: center.x + wx * s + off.width,
                                       y: center.y + wy * s + off.height)
                    }

                    let hasSelection = selectedNodeID != nil

                    // Edges — dim layer first, bright on top.
                    let groups = edgeGroups(toScreen: toScreen,
                                            highlight: highlight,
                                            hasSelection: hasSelection)
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

                    // Nodes
                    let nodeRadius: CGFloat = 6
                    let labelEnabled = s > 0.55
                    for node in store.graph.nodes.values {
                        guard let worldPoint = layout[node.id] else { continue }
                        let p = toScreen(node.id, worldPoint)
                        let inHighlight = !hasSelection || highlight.contains(node.id)

                        let fill = nodeColor(node).opacity(inHighlight ? 1.0 : dimOpacity)
                        let rect = CGRect(x: p.x - nodeRadius, y: p.y - nodeRadius,
                                          width: nodeRadius * 2, height: nodeRadius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(fill))

                        if selectedNodeID == node.id {
                            let r: CGFloat = nodeRadius + 3
                            let ring = CGRect(x: p.x - r, y: p.y - r,
                                              width: r * 2, height: r * 2)
                            context.stroke(Path(ellipseIn: ring),
                                           with: .color(.accentColor), lineWidth: 2)
                        }

                        if labelEnabled && inHighlight {
                            let resolved = context.resolve(
                                Text(node.label).font(.system(size: 10))
                            )
                            context.draw(resolved,
                                         at: CGPoint(x: p.x, y: p.y + nodeRadius + 8),
                                         anchor: .top)
                        }
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
            .onTapGesture(coordinateSpace: .local) { point in
                handleTap(at: point, size: geo.size)
            }
            .contextMenu { selectedNodeMenu() }
        }
        .task(id: store.graph.nodes.count) {
            await rebuildLayoutPipeline()
        }
    }

    // MARK: - Layout pipeline (circular seed → background force-directed)

    private func rebuildLayoutPipeline() async {
        let snapshotNodes = Array(store.graph.nodes.values)
        let nodeIDs = snapshotNodes.map { $0.id }
        let edgePairs = store.graph.edges.map { ($0.sourceID, $0.targetID) }

        // 1. Cheap circular seed so something appears immediately.
        layout = makeCircularLayout(for: nodeIDs)
        layoutKind = .circular
        rebuildAdjacency()

        guard !nodeIDs.isEmpty else { return }

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
    }

    // MARK: - Hit testing

    private func handleTap(at point: CGPoint, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let worldX = (point.x - center.x - offset.width) / scale
        let worldY = (point.y - center.y - offset.height) / scale
        let world = CGPoint(x: worldX, y: worldY)

        let tapRadius: CGFloat = 12 / scale
        var bestID: String?
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for (id, p) in layout {
            let d = hypot(p.x - world.x, p.y - world.y)
            if d < tapRadius && d < bestDistance {
                bestDistance = d
                bestID = id
            }
        }
        selectedNodeID = bestID
    }

    // MARK: - Edge batching

    private struct EdgeBatches {
        var dim: [EdgeGroup] = []
        var bright: [EdgeGroup] = []
    }

    private func edgeGroups(toScreen: (String, CGPoint) -> CGPoint,
                            highlight: Set<String>,
                            hasSelection: Bool) -> EdgeBatches {
        var dimByColor: [String: (Color, Path)] = [:]
        var brightByColor: [String: (Color, Path)] = [:]

        for edge in store.graph.edges {
            guard let a = layout[edge.sourceID], let b = layout[edge.targetID] else { continue }
            let color = edgeColor(edge)
            let key = colorKey(color)
            let isBright = !hasSelection ||
                (highlight.contains(edge.sourceID) && highlight.contains(edge.targetID))

            if isBright {
                var entry = brightByColor[key] ?? (color, Path())
                entry.1.move(to: toScreen(edge.sourceID, a))
                entry.1.addLine(to: toScreen(edge.targetID, b))
                brightByColor[key] = entry
            } else {
                var entry = dimByColor[key] ?? (color, Path())
                entry.1.move(to: toScreen(edge.sourceID, a))
                entry.1.addLine(to: toScreen(edge.targetID, b))
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
            Button("Clear selection") { selectedNodeID = nil }
            Button("Expand neighbors") { /* TODO */ }
            Button("Pin node") { /* TODO */ }
            Button("Focus subnet") { /* TODO */ }
            Button("Trace lineage") { /* TODO */ }
        } else {
            Text("No node selected")
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
