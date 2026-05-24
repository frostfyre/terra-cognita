import SwiftUI

struct GraphView: View {
    @StateObject private var store: GraphStore
    @State private var selectedNodeID: String?
    @State private var activeLens: Lens = .all
    @State private var showingSearch: Bool = false
    /// When non-nil, the canvas is "inside" this node's subnet: only
    /// that subnet's hub + members are visible.
    @State private var subnetRootID: String?
    /// Structural decomposition into hubs + assigned members. Computed
    /// once when the graph loads.
    @State private var subnets: SubnetTopology = SubnetTopology()

    init(store: GraphStore) {
        _store = StateObject(wrappedValue: store)
    }

    init() {
        _store = StateObject(wrappedValue: GraphStore())
    }

    var body: some View {
        ZStack(alignment: .top) {
            GraphCanvasView(
                store: store,
                selectedNodeID: $selectedNodeID,
                subnetRootID: $subnetRootID,
                visibleNodeFilter: visibleFilter
            )

            // Top bar — lens picker + (optional) subnet badge + find button
            HStack(spacing: 8) {
                LensPicker(active: $activeLens, store: store)
                if let rootID = subnetRootID,
                   let root = store.graph.nodes[rootID] {
                    SubnetBadge(label: root.label) { subnetRootID = nil }
                }
                Spacer()
                Button {
                    showingSearch = true
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Find a node by name (⌘F)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial)

            // Load-status pill (bottom)
            if !store.loadStatus.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text(store.loadStatus)
                            .font(.caption)
                            .padding(6)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                        Spacer()
                    }
                }
            }

            if showingSearch {
                VStack {
                    Spacer().frame(height: 56)
                    NodeSearchView(store: store) { chosen in
                        if let id = chosen { selectedNodeID = id }
                        showingSearch = false
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // Invisible Escape catcher — exits subnet mode when active.
            // (SwiftUI lacks a direct top-level keyboard handler outside
            // a focused field, so this gives us one without stealing
            // any user-visible behaviour.)
            if subnetRootID != nil {
                Button("") { subnetRootID = nil }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
        .onAppear { store.loadDefaultVault() }
        .onChange(of: store.graph.nodes.count) { _, _ in
            subnets = SubnetTopology.compute(from: store.graph)
        }
        .inspector(isPresented: Binding(
            get: { selectedNodeID != nil },
            set: { if !$0 { selectedNodeID = nil } }
        )) {
            if let id = selectedNodeID {
                NodeInspectorView(
                    nodeID: id,
                    store: store,
                    onSelectNode: { newID in selectedNodeID = newID }
                )
                .inspectorColumnWidth(min: 280, ideal: 360, max: 520)
            }
        }
    }

    /// Composed visible-node filter:
    ///   - Top level: only hubs + wilderness (subnet members are hidden)
    ///   - Inside a subnet: only that subnet's hub + its members
    /// All paths are then intersected with the active lens.
    private var visibleFilter: ((Node) -> Bool)? {
        let lens = activeLens.makeFilter()
        let topology = subnets
        if let rootID = subnetRootID {
            return { node in
                topology.isInside(node.id, subnet: rootID)
                    && (lens?(node) ?? true)
            }
        }
        return { node in
            topology.isTopLevel(node.id)
                && (lens?(node) ?? true)
        }
    }
}

// MARK: - Subnet badge

private struct SubnetBadge: View {
    let label: String
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.left").font(.caption)
            Text(label).font(.caption).lineLimit(1)
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.purple.opacity(0.18), in: Capsule())
        .foregroundStyle(.purple)
        .help("Exit subnet (Esc)")
        .onTapGesture { onExit() }
    }
}

// MARK: - Lenses

/// A semantic view over the graph. Each lens decides which nodes are
/// visible (and by extension, which edges — only edges with both endpoints
/// visible are drawn).
enum Lens: Hashable, CaseIterable, Identifiable {
    case all
    case people
    case concepts
    case institutions
    case events
    case works

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "All"
        case .people: return "People"
        case .concepts: return "Concepts"
        case .institutions: return "Institutions"
        case .events: return "Events"
        case .works: return "Works"
        }
    }

    var icon: String {
        switch self {
        case .all: return "circle.grid.3x3.fill"
        case .people: return "person.fill"
        case .concepts: return "lightbulb.fill"
        case .institutions: return "building.2.fill"
        case .events: return "calendar"
        case .works: return "book.fill"
        }
    }

    /// Build a closure `(Node) -> Bool` that decides whether a node is
    /// visible under the lens. `nil` means "include everything" (faster
    /// than always returning true; canvas can skip the visibility check).
    func makeFilter() -> ((Node) -> Bool)? {
        switch self {
        case .all: return nil
        case .people:        return { $0.type == "person" }
        case .concepts:      return { $0.type == "concept" }
        case .institutions:  return { $0.type == "institution" }
        case .events:        return { $0.type == "event" }
        case .works:         return { $0.type == "work" }
        }
    }
}

private struct LensPicker: View {
    @Binding var active: Lens
    @ObservedObject var store: GraphStore

    var body: some View {
        Menu {
            ForEach(Lens.allCases) { lens in
                Button {
                    active = lens
                } label: {
                    Label(lens.label + countSuffix(lens), systemImage: lens.icon)
                }
            }
        } label: {
            Label(active.label, systemImage: active.icon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func countSuffix(_ lens: Lens) -> String {
        guard let filter = lens.makeFilter() else { return "" }
        let n = store.graph.nodes.values.filter(filter).count
        return n > 0 ? " (\(n))" : ""
    }
}
