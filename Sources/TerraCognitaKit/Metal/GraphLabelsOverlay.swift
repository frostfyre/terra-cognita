import SwiftUI

/// SwiftUI label layer for the Metal "Pro" renderer. Sits on top of
/// the MTKView, projects each visible node's world position to
/// screen space (parallax-aware), and mounts a Text pill there —
/// drift-synced to the GPU wobble via `GraphDrift`.
///
/// Visibility rules mirror the Canvas path:
///   • zoom-gated (`scale > 0.85`) OR a selection is active,
///   • only in-highlight nodes get labels while a selection is
///     active (dimmed background nodes stay quiet),
///   • the selected node's label gets the gold selection treatment,
///   • label opacity follows the node's depth cue.
///
/// Cost: O(N) viewport-cull per body re-eval (one float compare per
/// node). On 15K nodes that's a tight loop on modern silicon — fine
/// at 60Hz. ForEach mounts only the visible subset (50–500 typical).
struct GraphLabelsOverlay: View {
    @ObservedObject var store: GraphStore
    let projection: GraphProjection
    let visibleNodeFilter: ((Node) -> Bool)?
    let selectedNodeID: String?
    /// N-hop BFS neighborhood of the selection — computed by the
    /// parent (it needs the set for dimming anyway). Empty when
    /// nothing is selected.
    let highlight: Set<String>

    private static let labelText = Color(white: 0.82)
    private static let selectionGold = Color(red: 1.00, green: 0.78, blue: 0.30)

    private var hasSelection: Bool { selectedNodeID != nil }
    private var shouldShow: Bool {
        projection.camera.scale > 0.85 || hasSelection
    }

    var body: some View {
        if shouldShow {
            // TimelineView so labels re-position at display refresh
            // rate and stay glued to the GPU-side drift wobble.
            TimelineView(.animation) { _ in
                let t = GraphDrift.now()
                ZStack(alignment: .topLeading) {
                    ForEach(visibleNodes(), id: \.node.id) { hit in
                        let drift = GraphDrift.offset(seed: hit.seed, time: t)
                        labelPill(for: hit)
                            .position(x: hit.screen.x + drift.x,
                                      y: hit.screen.y + drift.y)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func labelPill(for hit: LabelHit) -> some View {
        if hit.isSelected {
            Text(hit.node.label)
                .font(.system(size: 11).weight(.semibold))
                .foregroundStyle(Self.labelText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Self.selectionGold.opacity(0.32), in: Capsule())
                .overlay(Capsule().stroke(Self.selectionGold.opacity(0.75),
                                          lineWidth: 1))
                .shadow(color: .black.opacity(0.85), radius: 2, y: 2)
        } else {
            Text(hit.node.label)
                .font(.system(size: 10))
                .foregroundStyle(Self.labelText.opacity(hit.opacity))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.40), in: Capsule())
                .shadow(color: .black.opacity(0.75), radius: 1.2, y: 1)
        }
    }

    /// Walk all nodes once, project to screen with parallax, filter
    /// to viewport with a generous off-edge margin so labels don't
    /// pop on the boundary as the camera pans.
    private func visibleNodes() -> [LabelHit] {
        let viewSize = projection.viewSize
        let xMin: CGFloat = -120
        let xMax = viewSize.width + 120
        let yMin: CGFloat = -40
        let yMax = viewSize.height + 40
        var out: [LabelHit] = []
        out.reserveCapacity(256)
        for node in store.graph.nodes.values {
            if let visibleNodeFilter, !visibleNodeFilter(node) { continue }
            let isSelected = node.id == selectedNodeID
            // While a selection is active, dimmed background nodes
            // don't get labels — they're receding, not narrating.
            if hasSelection && !highlight.contains(node.id) && !isSelected { continue }
            guard let p = store.layoutPosition(for: node.id) else { continue }
            let depth = node.depth(in: store.config)
            let s = projection.screenPoint(world: p, depth: depth)
            if s.x < xMin || s.x > xMax || s.y < yMin || s.y > yMax { continue }
            let depthOpacityMul = 0.55 + 0.45 * depth
            out.append(LabelHit(node: node,
                                screen: s,
                                seed: GraphMetalView.hashSeed(for: node.id),
                                opacity: max(0.85, depthOpacityMul),
                                isSelected: isSelected))
        }
        return out
    }

    private struct LabelHit {
        let node: Node
        let screen: CGPoint
        let seed: Float
        let opacity: Double
        let isSelected: Bool
    }
}
