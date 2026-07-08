import SwiftUI

/// Hero-image discs for the Metal "Pro" renderer. When zoomed in
/// past the same 1.3× threshold the Canvas path uses, nodes with a
/// `hero:` attribute swap their flat GPU disc for the image,
/// clipped to the node circle and drift-synced so it stays glued to
/// the wobbling disc underneath.
///
/// Lives as a SwiftUI overlay rather than a GPU texture pass: above
/// the zoom threshold only a handful of nodes are on screen, so the
/// per-view cost is small and we avoid building a texture atlas.
/// Images load lazily via the shared `HeroImageLoader` and cache for
/// the overlay's lifetime.
struct GraphHeroImagesOverlay: View {
    @ObservedObject var store: GraphStore
    let projection: GraphProjection
    let visibleNodeFilter: ((Node) -> Bool)?
    /// Degree-coupled world radius from the parent's adjacency cache
    /// (avoids an O(E) walk per node per frame).
    let nodeWorldRadius: (String) -> CGFloat

    /// Below this zoom level the flat GPU fills stand alone; above
    /// it, hero discs mount. Matches `GraphCanvasView`.
    private let zoomThreshold: CGFloat = 1.3

    @State private var heroImages: [String: Image] = [:]
    @State private var loadsInFlight: Set<String> = []

    var body: some View {
        if projection.camera.scale > zoomThreshold {
            TimelineView(.animation) { _ in
                let t = GraphDrift.now()
                ZStack(alignment: .topLeading) {
                    ForEach(visibleHeroNodes(), id: \.node.id) { hit in
                        let drift = GraphDrift.offset(seed: hit.seed, time: t)
                        // ZStack (not Group) so the container exists
                        // even before the image loads — `onAppear`
                        // is what kicks off the lazy load, and a
                        // childless Group never fires it.
                        ZStack {
                            if let image = heroImages[hit.node.id] {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: hit.radius * 2,
                                           height: hit.radius * 2)
                                    .clipShape(Circle())
                                    .opacity(hit.opacity)
                            }
                        }
                        .position(x: hit.screen.x + drift.x,
                                  y: hit.screen.y + drift.y)
                        .allowsHitTesting(false)
                        .onAppear { triggerLoadIfNeeded(for: hit.node) }
                    }
                }
            }
        }
    }

    private struct HeroHit {
        let node: Node
        let screen: CGPoint
        let radius: CGFloat
        let opacity: Double
        let seed: Float
    }

    private func visibleHeroNodes() -> [HeroHit] {
        let viewSize = projection.viewSize
        var out: [HeroHit] = []
        for node in store.graph.nodes.values {
            guard node.attributes["hero"]?.isEmpty == false else { continue }
            if let visibleNodeFilter, !visibleNodeFilter(node) { continue }
            guard let world = store.layoutPosition(for: node.id) else { continue }
            let depth = node.depth(in: store.config)
            let screen = projection.screenPoint(world: world, depth: depth)
            if screen.x < -64 || screen.x > viewSize.width + 64
                || screen.y < -64 || screen.y > viewSize.height + 64 {
                continue
            }
            let radius = projection.screenRadius(
                worldRadius: nodeWorldRadius(node.id), depth: depth)
            // The hero disc inherits the node's depth opacity cue so
            // background-era heroes read as memory too.
            out.append(HeroHit(node: node,
                               screen: screen,
                               radius: radius,
                               opacity: 0.55 + 0.45 * depth,
                               seed: GraphMetalView.hashSeed(for: node.id)))
        }
        return out
    }

    /// Fire-and-forget background load of a node's hero image —
    /// same resolution rules as the Canvas path (shared loader).
    private func triggerLoadIfNeeded(for node: Node) {
        guard heroImages[node.id] == nil,
              !loadsInFlight.contains(node.id),
              let hero = node.attributes["hero"], !hero.isEmpty,
              let path = node.filePath else { return }
        loadsInFlight.insert(node.id)
        let nodeID = node.id
        let nodeDir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let atlas = store.writableAtlasURL
        Task.detached(priority: .utility) {
            let image = await HeroImageLoader.load(named: hero, near: nodeDir, atlas: atlas)
            await MainActor.run {
                if let image { heroImages[nodeID] = image }
                loadsInFlight.remove(nodeID)
            }
        }
    }
}
