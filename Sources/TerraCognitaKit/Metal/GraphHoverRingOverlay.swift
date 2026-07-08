import SwiftUI

/// Soft halo around whichever node the pointer is over. Mirrors the
/// Canvas path's hover ring — a node-tinted fill + white stroke 5pt
/// outside the disc — and gives pointer users (Mac, iPad) the same
/// "this is targetable" feedback touch users get on tap. No-op on
/// iPhone where there's no pointer.
///
/// Receives the hovered id from the parent gesture overlay; doesn't
/// do hit-testing here so we don't double-walk the node array.
struct GraphHoverRingOverlay: View {
    @ObservedObject var store: GraphStore
    let hoveredNodeID: String?
    let projection: GraphProjection

    var body: some View {
        if let id = hoveredNodeID,
           let node = store.graph.nodes[id],
           let world = store.layoutPosition(for: id) {
            let depth = node.depth(in: store.config)
            let radius = projection.screenRadius(
                worldRadius: store.nodeRadius(for: id),
                depth: depth) + 5
            let baseScreen = projection.screenPoint(world: world, depth: depth)
            let seed = GraphMetalView.hashSeed(for: id)
            let tint = store.config.typeSpec(named: node.type)?.color
                ?? .white.opacity(0.9)
            // TimelineView so the hover ring drifts with the node
            // disc; otherwise the ring stays anchored and the disc
            // visibly slides out from under it.
            TimelineView(.animation) { _ in
                let drift = GraphDrift.offset(seed: seed, time: GraphDrift.now())
                let screen = CGPoint(x: baseScreen.x + drift.x,
                                     y: baseScreen.y + drift.y)
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: radius * 2, height: radius * 2)
                    Circle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                }
                .position(screen)
                .allowsHitTesting(false)
            }
        }
    }
}
