import SwiftUI

/// SwiftUI selection treatment for the Metal "Pro" renderer —
/// mirrors the Canvas path's full stack:
///   1. soft breathing halo (four stacked translucent gold rings,
///      slow sinusoid so it never feels static)
///   2. core fill (the node itself, redrawn on top with the hardest
///      shadow on the canvas + the lit-from-upper-left highlight,
///      pulsed briefly on selection change)
///   3. sparse orbital sparks (six slow gold specks)
///
/// Sits above the Metal layer in the ZStack so it's never overdrawn
/// by node discs. Drift-synced to the GPU wobble via `GraphDrift`.
struct GraphSelectionHaloOverlay: View {
    @ObservedObject var store: GraphStore
    let selectedNodeID: String?
    let projection: GraphProjection

    private static let selectionGold = Color(red: 1.00, green: 0.78, blue: 0.30)
    /// Selection pulse — set to 1 on selection change, eased back
    /// to 0 over 0.4s. Scales the core disc + halo radii.
    @State private var pulse: CGFloat = 0

    var body: some View {
        if let id = selectedNodeID,
           let node = store.graph.nodes[id],
           let world = store.layoutPosition(for: id) {
            // Selected node ignores the depth size cue — it's
            // conceptually "most foreground" (matches Canvas).
            let baseRadius = store.nodeRadius(for: id) * projection.zoomFactor
            let depth = node.depth(in: store.config)
            let baseScreen = projection.screenPoint(world: world, depth: depth)
            let seed = GraphMetalView.hashSeed(for: id)
            let fill = store.config.typeSpec(named: node.type)?.color
                ?? .white.opacity(0.9)
            // TimelineView so the halo breathes, the sparks orbit,
            // and everything drifts with the GPU-side wobble.
            TimelineView(.animation) { _ in
                let t = GraphDrift.now()
                let drift = GraphDrift.offset(seed: seed, time: t)
                let screen = CGPoint(x: baseScreen.x + drift.x,
                                     y: baseScreen.y + drift.y)
                let nodeRadius = baseRadius * (1 + pulse)
                let breath = 1.0 + 0.18 * sin(t * 1.3)

                ZStack {
                    // --- Glow halo — four concentric translucent
                    // fills approximate a soft radial gradient.
                    // Largest first so smaller rings paint on top.
                    ForEach(haloRings(nodeRadius: nodeRadius,
                                      breath: breath).reversed(),
                            id: \.radius) { ring in
                        Circle()
                            .fill(Self.selectionGold.opacity(ring.alpha))
                            .frame(width: ring.radius * 2,
                                   height: ring.radius * 2)
                            .position(screen)
                    }

                    // --- Core — the node disc redrawn on top of the
                    // glow with the hardest shadow on the canvas and
                    // the same lit-from-upper-left highlight the GPU
                    // applies to foreground fills.
                    Circle()
                        .fill(fill)
                        .overlay(litHighlight)
                        .frame(width: nodeRadius * 2, height: nodeRadius * 2)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 5)
                        .position(screen)

                    // --- Orbital sparks — six small specks at
                    // ~9 sec/turn, each with a slow pulse.
                    ForEach(0..<6, id: \.self) { i in
                        let baseAngle = Double(i) / 6 * .pi * 2
                        let angle = baseAngle + t * 0.7
                        let wobble = sin(t * 2.1 + Double(i)) * 1.2
                        let orbitR = nodeRadius + 14 + CGFloat(wobble)
                        let sparkPulse = 0.55 + 0.35 * sin(t * 1.7 + Double(i) * 0.9)
                        Circle()
                            .fill(Self.selectionGold.opacity(sparkPulse * 0.7))
                            .frame(width: 2.8, height: 2.8)
                            .position(x: screen.x + orbitR * CGFloat(cos(angle)),
                                      y: screen.y + orbitR * CGFloat(sin(angle)))
                    }
                }
                .allowsHitTesting(false)
            }
            .onAppear { triggerPulse() }
            .onChange(of: selectedNodeID) { _, _ in triggerPulse() }
        }
    }

    private struct HaloRing: Hashable {
        let radius: CGFloat
        let alpha: Double
    }

    private func haloRings(nodeRadius: CGFloat,
                           breath: Double) -> [HaloRing] {
        [
            HaloRing(radius: nodeRadius + 4  * CGFloat(breath), alpha: 0.42),
            HaloRing(radius: nodeRadius + 10 * CGFloat(breath), alpha: 0.22),
            HaloRing(radius: nodeRadius + 18 * CGFloat(breath), alpha: 0.10),
            HaloRing(radius: nodeRadius + 30 * CGFloat(breath), alpha: 0.04),
        ]
    }

    /// Lit-from-upper-left radial highlight — same stops as the
    /// Canvas path's `applyNodeHighlight` and the GPU fragment
    /// shader, so the overlaid core reads as the same material.
    private var litHighlight: some View {
        GeometryReader { geo in
            let w = geo.size.width
            RadialGradient(
                stops: [
                    .init(color: .white.opacity(0.55), location: 0.0),
                    .init(color: .white.opacity(0.18), location: 0.35),
                    .init(color: .white.opacity(0.0),  location: 0.85),
                ],
                center: .init(x: 0.5 - 0.22, y: 0.5 - 0.22),
                startRadius: 0,
                endRadius: w * 0.7
            )
        }
        .clipShape(Circle())
    }

    private func triggerPulse() {
        pulse = 1
        withAnimation(.easeOut(duration: 0.4)) {
            pulse = 0
        }
    }
}
