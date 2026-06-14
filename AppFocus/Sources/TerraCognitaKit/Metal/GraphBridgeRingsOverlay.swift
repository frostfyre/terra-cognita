import SwiftUI

/// Dashed gold rings around topology-bridge nodes (Systems lens) —
/// mirrors the Canvas path's bridge treatment. Bridge sets are
/// small (a handful of nodes per atlas), so a SwiftUI overlay is
/// cheaper than a dedicated GPU pass. Drift-synced and
/// viewport-culled.
struct GraphBridgeRingsOverlay: View {
    @ObservedObject var store: GraphStore
    let bridgeNodeIDs: Set<String>
    let visibleNodeFilter: ((Node) -> Bool)?
    let projection: GraphProjection

    private static let bridgeGold = Color(red: 1.00, green: 0.78, blue: 0.30)

    var body: some View {
        if !bridgeNodeIDs.isEmpty {
            TimelineView(.animation) { _ in
                let t = GraphDrift.now()
                ZStack(alignment: .topLeading) {
                    ForEach(visibleBridges(), id: \.id) { hit in
                        let drift = GraphDrift.offset(seed: hit.seed, time: t)
                        Circle()
                            .stroke(Self.bridgeGold.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 1.2,
                                                       dash: [3, 3]))
                            .frame(width: hit.ringRadius * 2,
                                   height: hit.ringRadius * 2)
                            .position(x: hit.screen.x + drift.x,
                                      y: hit.screen.y + drift.y)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private struct BridgeHit {
        let id: String
        let screen: CGPoint
        let ringRadius: CGFloat
        let seed: Float
    }

    private func visibleBridges() -> [BridgeHit] {
        let viewSize = projection.viewSize
        var out: [BridgeHit] = []
        out.reserveCapacity(bridgeNodeIDs.count)
        for id in bridgeNodeIDs {
            guard let node = store.graph.nodes[id] else { continue }
            if let visibleNodeFilter, !visibleNodeFilter(node) { continue }
            guard let world = store.layoutPosition(for: id) else { continue }
            let depth = node.depth(in: store.config)
            let screen = projection.screenPoint(world: world, depth: depth)
            if screen.x < -64 || screen.x > viewSize.width + 64
                || screen.y < -64 || screen.y > viewSize.height + 64 {
                continue
            }
            // Ring sits 4pt outside the drawn disc (depth size cue
            // included, matching the GPU's radius).
            let ringRadius = projection.screenRadius(
                worldRadius: store.nodeRadius(for: id), depth: depth) + 4
            out.append(BridgeHit(id: id,
                                 screen: screen,
                                 ringRadius: ringRadius,
                                 seed: GraphMetalView.hashSeed(for: id)))
        }
        return out
    }
}
