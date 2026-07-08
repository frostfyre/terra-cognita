import SwiftUI

/// Idle-state ambient puff for the Metal "Pro" renderer. When
/// nothing is selected, `GraphMetalView`'s ambient cycle picks a
/// random (degree-weighted) node every few seconds; this overlay
/// breathes it up to ~1.9× radius and back over 2.4s with a hard
/// drop shadow, an accent ring, and an enlarged label — mirroring
/// the Canvas path's `deferredAmbient` pass so the graph feels
/// alive while the user reads.
struct GraphAmbientPuffOverlay: View {
    @ObservedObject var store: GraphStore
    /// The currently-puffed node, or nil. Parent passes nil while a
    /// selection is active so the puff never fights deliberate focus.
    let ambientNodeID: String?
    /// Puff start in `GraphDrift.now()` time.
    let startTime: TimeInterval?
    let projection: GraphProjection

    private static let labelText = Color(white: 0.82)
    private let puffDuration: Double = 2.4

    var body: some View {
        if let id = ambientNodeID,
           let start = startTime,
           let node = store.graph.nodes[id],
           let world = store.layoutPosition(for: id) {
            let depth = node.depth(in: store.config)
            let baseRadius = projection.screenRadius(
                worldRadius: store.nodeRadius(for: id), depth: depth)
            let baseScreen = projection.screenPoint(world: world, depth: depth)
            let seed = GraphMetalView.hashSeed(for: id)
            let fill = store.config.typeSpec(named: node.type)?.color
                ?? .white.opacity(0.9)
            TimelineView(.animation) { _ in
                let t = GraphDrift.now()
                let elapsed = t - start
                if elapsed >= 0, elapsed <= puffDuration {
                    let puff = CGFloat(sin(.pi * (elapsed / puffDuration)))
                    let drift = GraphDrift.offset(seed: seed, time: t)
                    let screen = CGPoint(x: baseScreen.x + drift.x,
                                         y: baseScreen.y + drift.y)
                    let drawRadius = baseRadius * (1 + puff * 0.9)
                    let ringRadius = drawRadius + 2 + puff * 2

                    ZStack {
                        Circle()
                            .fill(fill)
                            .frame(width: drawRadius * 2, height: drawRadius * 2)
                            .shadow(color: .black.opacity(0.55), radius: 2.5, y: 4)
                            .position(screen)
                        Circle()
                            .stroke(Color.accentColor.opacity(0.55 * puff),
                                    lineWidth: 1.5)
                            .frame(width: ringRadius * 2, height: ringRadius * 2)
                            .position(screen)
                        Text(node.label)
                            .font(.system(size: 10 + puff * 3).weight(.medium))
                            .foregroundStyle(Self.labelText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.45), in: Capsule())
                            .shadow(color: .black.opacity(0.8), radius: 1.6, y: 1.5)
                            .position(screen)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }
}
