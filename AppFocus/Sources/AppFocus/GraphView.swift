import SwiftUI

struct GraphView: View {
    @StateObject private var store: GraphStore
    /// Selected node lives here so the canvas, the inspector, and the
    /// search popover can all observe and mutate it.
    @State private var selectedNodeID: String?
    /// Active lens filtering. `nil` = show everything.
    @State private var activeLens: Lens = .all
    @State private var showingSearch: Bool = false

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
                visibleNodeFilter: activeLens.makeFilter()
            )

            // Top bar — lens picker + find button
            HStack(spacing: 8) {
                LensPicker(active: $activeLens, store: store)
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

            // Search popover (fade in/out)
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
        }
        .onAppear { store.loadDefaultVault() }
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

