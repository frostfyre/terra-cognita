import SwiftUI

struct GraphView: View {
    @StateObject private var store: GraphStore

    // Use this when you already have a store you want to observe
    init(store: GraphStore) {
        _store = StateObject(wrappedValue: store)
    }

    // Convenience initializer so you can write `GraphView()`
    init() {
        _store = StateObject(wrappedValue: GraphStore())
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GraphCanvasView(store: store)
            if !store.loadStatus.isEmpty {
                Text(store.loadStatus)
                    .font(.caption)
                    .padding(6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
        .onAppear { store.loadDefaultVault() }
    }
}

