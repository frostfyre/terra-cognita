import SwiftUI

struct GraphView: View {
    @StateObject private var store: GraphStore
    /// Selected node lives here so the canvas and the inspector can both
    /// observe and mutate it — clicking a link in the inspector navigates
    /// the graph, and clicking a node in the canvas opens that node in
    /// the inspector.
    @State private var selectedNodeID: String?

    init(store: GraphStore) {
        _store = StateObject(wrappedValue: store)
    }

    init() {
        _store = StateObject(wrappedValue: GraphStore())
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GraphCanvasView(store: store, selectedNodeID: $selectedNodeID)
            if !store.loadStatus.isEmpty {
                Text(store.loadStatus)
                    .font(.caption)
                    .padding(6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
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
