import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct GraphCanvasView: View {
    @ObservedObject var store: GraphStore

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScaleValue: CGFloat = 1
    @State private var canvasSize: CGSize = .zero

    /// Per-node manually-pinned positions in world space. Pinned nodes
    /// are not displaced by future automatic layouts.
    @State private var pinnedPositions: [String: CGPoint] = [:]
    /// While the user is dragging a node, this holds its id.
    @State private var draggingNodeID: String?
    /// While the user is panning (drag started on empty canvas), this
    /// holds the `offset` at the start of the drag so each onChanged
    /// frame can compute the new offset relative to it.
    @State private var panAnchor: CGSize?



    /// Currently hovered node id (iPad pointer / Mac mouse). Drives the
    /// soft hover ring drawn in the Canvas pass — gives pointer users
    /// the same "this is targetable" feedback touch users get via tap.
    @State private var hoveredNodeID: String?

    /// Cached hero images keyed by node id. Populated lazily when a
    /// node with a `hero:` attribute first enters the render loop and
    /// the canvas is zoomed in past `heroImageZoomThreshold`. Drawn
    /// clipped to the node circle in place of the flat color fill.
    @State private var heroImages: [String: Image] = [:]
    /// Tracks which hero loads are in flight so we don't kick off
    /// duplicate tasks on every frame.
    @State private var heroLoadInFlight: Set<String> = []
    /// Below this zoom level we just draw flat node fills. Above it,
    /// nodes with hero images swap their fill for the image disc.
    private let heroImageZoomThreshold: CGFloat = 1.3

    /// When nothing is selected, the canvas periodically "puffs" a random
    /// node so the graph feels alive and the eye gets surfaced to nodes
    /// it might not otherwise notice.
    @State private var ambientHighlightID: String?
    @State private var ambientHighlightStart: TimeInterval?
    private let ambientPuffDuration: Double = 2.4

    /// Selection halo / spark color. Warm gold to echo the app icon's
    /// "illuminated point" — distinct from the cooler `.accentColor`
    /// used by the ambient puff so the two states read differently.
    private let selectionGold = Color(red: 1.00, green: 0.78, blue: 0.30)

    /// Zoom clamps. `minScale` is generous enough to fit the largest
    /// vaults we expect on iPhone — the prior 0.25 floor wasn't far
    /// enough out to see a multi-hundred-node graph end-to-end.
    private let minScale: CGFloat = 0.1
    private let maxScale: CGFloat = 4.0

    /// Label text color — a warm-ish ~80% white. Pure `.primary`
    /// (full white) felt harsh on the indigo gradient; this sits
    /// slightly off-white so titles read as warm rather than clinical
    /// while still popping off the ~30–40% grey pills behind them.
    private let labelText = Color(white: 0.82)
    /// Owned by `GraphView` so the inspector panel can drive it too.
    @Binding var selectedNodeID: String?
    /// A node freshly written by `GraphStore.createNode`. The canvas
    /// pins it at its spawn world point, selects it, animates a frame
    /// onto it, and then clears the binding.
    @Binding var pendingNewNode: PendingNewNode?
    /// Optional node-visibility filter (lens). `nil` means show everything.
    /// Edges are visible only when both endpoints pass the filter.
    var visibleNodeFilter: ((Node) -> Bool)? = nil
    /// Fires when the user long-presses *empty* canvas (no node under
    /// the press point). The argument is the press point in world
    /// coordinates so the host can spawn a new node there.
    var onLongPressEmptyWorld: ((CGPoint) -> Void)?
    /// Fires when the user long-presses *on a node*. The host opens a
    /// radial menu anchored to the press point.
    var onLongPressNode: ((_ nodeID: String, _ screenPoint: CGPoint) -> Void)?
    /// Trigger for "fit to view" — when this binding's value changes,
    /// the canvas animates scale + offset to frame every currently-
    /// visible node. The host increments to request a refit.
    @Binding var frameAllPulse: Int
    /// Wall-clock time of the most recent selection. Drives the
    /// "selected node briefly doubles in size" pulse.
    @State private var selectionPulseStart: TimeInterval?

    private let selectionPulseDuration: Double = 0.4

    /// Cached node positions in world space. Rewritten when the graph
    /// changes (first to a circular seed, then to a force-directed layout
    /// once the background computation finishes).
    @State private var layout: [String: CGPoint] = [:]
    /// The algorithm currently applied to `layout`. `nil` before any
    /// layout pass has run on the current vault. Phase 1 will expose
    /// this through a Layout menu so the user can switch algorithms;
    /// today the pipeline only writes `.circular` → `.forceDirected`.
    @State private var layoutAlgorithm: LayoutAlgorithm? = nil

    /// Undirected adjacency, rebuilt when the graph changes. Used for the
    /// "dim everything outside the N-hop neighborhood of the selection".
    @State private var adjacency: [String: [String]] = [:]

    /// Nodes sorted back-to-front by depth (oldest era first). Rebuilt
    /// when the graph changes so we don't pay for an O(n log n) sort on
    /// every Canvas redraw.
    @State private var depthOrderedNodes: [Node] = []

    /// Deep-background specks (a sparse star-field) seeded once on
    /// appear. They drift in world space with the maximum parallax so
    /// they appear "behind" everything when the user pans.
    @State private var atmosphereSpecks: [AtmosphereSpeck] = []

    private struct AtmosphereSpeck {
        var x: CGFloat       // world x
        var y: CGFloat       // world y
        var radius: CGFloat  // 0.6 – 1.6 px
        var phase: Double    // twinkle phase
    }


    /// How many BFS hops from the selected node remain at full opacity.
    private let highlightDepth = 1

    /// Opacity for nodes/edges outside the highlight set when a node is
    /// selected. 1.0 when no selection.
    private let dimOpacity: Double = 0.10

    /// Edges grouped by stroke color so the Canvas can issue one stroke
    /// per group instead of per edge.
    /// One edge stroke recorded for the render pass. Each edge gets
    /// its own gradient run from source node color → destination node
    /// color, so we no longer batch by uniform color. `curveSign` is
    /// +1 or -1 (derived from the edge id hash) so the quadratic
    /// curve always bends the same way for the same edge between
    /// frames — and A→B vs B→A bend opposite, keeping reciprocal
    /// edges visually distinct.
    private struct EdgeStroke {
        let from: CGPoint
        let to: CGPoint
        let colorFrom: Color
        let colorTo: Color
        let curveSign: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            let highlight = highlightedNodeIDs()
            let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
                Set(store.graph.nodes.values.filter(filter).map(\.id))
            }

            // 20 Hz strikes the visual sweet spot for the slow drift +
            // halo + twinkle aesthetic — 30 Hz looked the same but cost
            // ~50% more CPU in profiling.
            TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 86400)

                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let s = scale
                    let off = offset

                    // Ambient drift — sea-anemone style: each node has its
                    // own *frequency* per axis (not just phase), derived
                    // from hash bits, so the field looks fully independent.
                    // Angular velocities live in the 1–3 rad/sec range
                    // (period ~2-6s) and amplitudes are in screen pixels.
                    func driftFor(_ id: String) -> CGPoint {
                        let h = id.hashValue
                        let pa = Double(h & 0xFF) / 255.0 * 6.28318
                        let pb = Double((h >> 8) & 0xFF) / 255.0 * 6.28318
                        let pc = Double((h >> 16) & 0xFF) / 255.0 * 6.28318
                        let pd = Double((h >> 24) & 0xFF) / 255.0 * 6.28318
                        let fa = 1.0 + Double((h >> 32) & 0xFF) / 255.0 * 1.5
                        let fb = 1.4 + Double((h >> 40) & 0xFF) / 255.0 * 1.5
                        let fc = 1.0 + Double((h >> 48) & 0xFF) / 255.0 * 1.5
                        let fd = 1.4 + Double((h >> 56) & 0xFF) / 255.0 * 1.5
                        let x = sin(t * fa + pa) * 8.0 + sin(t * fb + pb) * 4.0
                        let y = cos(t * fc + pc) * 8.0 + cos(t * fd + pd) * 4.0
                        return CGPoint(x: x, y: y)
                    }

                    /// Parallax factor for a node at depth `d` (0 = deep, 1 = front).
                    /// Foreground tracks pan 1:1, deepest layer at ~55%.
                    func parallax(_ d: Double) -> CGFloat {
                        CGFloat(0.55 + 0.45 * d)
                    }

                    /// Project a world point to screen coordinates with
                    /// parallax (depth-aware offset) and ambient drift.
                    func toScreen(_ id: String, _ p: CGPoint, _ d: Double) -> CGPoint {
                        let drift = driftFor(id)
                        let pf = parallax(d)
                        return CGPoint(x: center.x + p.x * s + off.width * pf + drift.x,
                                       y: center.y + p.y * s + off.height * pf + drift.y)
                    }

                    let hasSelection = selectedNodeID != nil

                    // Background gradient is now a static SwiftUI
                    // `.background(RadialGradient(...))` underneath the
                    // Canvas — pulled out of the 20 Hz redraw and made
                    // unconditional so it still reads when zoomed past
                    // 1.5×. See the `.background` modifier below.
                    // Deep specks — only the ones that fall on-screen are
                    // drawn (off-screen culling cuts ~70% of the fills).
                    let speckParallax = parallax(0)
                    for speck in atmosphereSpecks {
                        let sx = center.x + speck.x * s + off.width * speckParallax
                        let sy = center.y + speck.y * s + off.height * speckParallax
                        if sx < -4 || sx > size.width + 4 ||
                           sy < -4 || sy > size.height + 4 { continue }
                        let twinkle = 0.45 + 0.4 * sin(t * 0.6 + speck.phase)
                        let r = CGFloat(speck.radius)
                        let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(.white.opacity(twinkle * 0.45)))
                    }

                    // Edges — quadratic-curve linear gradient where
                    // each endpoint carries the rendered opacity and
                    // saturation of the node it connects to. The
                    // edge-wide `edgeAlpha` scales the whole stroke;
                    // dim layer draws first so bright (highlight-
                    // subnet) edges sit on top.
                    // TODO: surface lineWidth / alpha / curve amount
                    // in a Display Settings panel (planned).
                    let groups = edgeGroups(toScreen: toScreen,
                                            highlight: highlight,
                                            hasSelection: hasSelection,
                                            visibleSet: visibleSet)
                    let edgeLineWidth: CGFloat = 0.85
                    let edgeAlpha = 0.50
                    // Two passes (dim then bright) so highlight-subnet
                    // edges land on top. Per-endpoint opacity / desat
                    // is already baked into the gradient colors above.
                    for stroke in (groups.dim + groups.bright) {
                        let path = edgePath(stroke)
                        context.stroke(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [
                                    stroke.colorFrom.opacity(edgeAlpha),
                                    stroke.colorTo.opacity(edgeAlpha)
                                ]),
                                startPoint: stroke.from,
                                endPoint: stroke.to
                            ),
                            lineWidth: edgeLineWidth
                        )
                    }

                    // Nodes — radius scales with degree (min 10, sqrt curve so
                    // hub nodes are clearly bigger without dwarfing leaves).
                    // Label visibility raised so labels only render once
                    // there's room (avoids the dense mass-of-text look).
                    let labelEnabled = s > 0.85
                    let selectionPulse: CGFloat = {
                        guard let start = selectionPulseStart else { return 0 }
                        let elapsed = t - start
                        guard elapsed >= 0, elapsed <= selectionPulseDuration else { return 0 }
                        let phase = elapsed / selectionPulseDuration
                        return CGFloat(sin(.pi * phase))
                    }()

                    // Idle-state ambient puff — only fires when nothing is
                    // selected. A sin curve scales the node radius up then
                    // back down over `ambientPuffDuration` seconds.
                    let ambientPuff: CGFloat = {
                        guard !hasSelection,
                              ambientHighlightID != nil,
                              let start = ambientHighlightStart else { return 0 }
                        let elapsed = t - start
                        guard elapsed >= 0, elapsed <= ambientPuffDuration else { return 0 }
                        let phase = elapsed / ambientPuffDuration
                        return CGFloat(sin(.pi * phase))
                    }()

                    // Defer the selected and currently-puffed nodes so they
                    // draw on top of everything else.
                    var deferredSelected: (Node, CGPoint, CGFloat)?
                    var deferredAmbient: (Node, CGPoint, CGFloat)?

                    // First pass — all non-deferred nodes, walked in
                    // depth order so the most "present" nodes overdraw
                    // older ones (DESIGN.md's "time as depth" idea).
                    for node in depthOrderedNodes {
                        if let visibleSet, !visibleSet.contains(node.id) { continue }
                        guard let worldPoint = effectivePosition(for: node.id) else { continue }
                        let depth = node.depth(in: store.config)
                        let p = toScreen(node.id, worldPoint, depth)
                        let isSelected = selectedNodeID == node.id
                        let isAmbient = !hasSelection
                            && ambientHighlightID == node.id
                            && ambientPuff > 0.01
                        let baseRadius = radiusFor(nodeID: node.id)

                        if isSelected {
                            deferredSelected = (node, p, baseRadius)
                            continue
                        }
                        if isAmbient {
                            deferredAmbient = (node, p, baseRadius)
                            continue
                        }

                        let inHighlight = !hasSelection || highlight.contains(node.id)
                        // Depth cue: nodes from older eras shrink slightly,
                        // lose opacity, AND lose saturation, so the
                        // foreground is visually dominant and the past
                        // reads as "washed out memory" rather than just dim.
                        let depthSizeMul = 0.85 + 0.35 * CGFloat(depth)
                        let depthOpacityMul = 0.55 + 0.45 * depth
                        let drawRadius = baseRadius * depthSizeMul
                        let opacity = (inHighlight ? 1.0 : dimOpacity) * depthOpacityMul
                        // Up to 55% of saturation drained at maximum depth-back.
                        let desaturation = CGFloat(1.0 - depth) * 0.55
                        let fill = nodeColor(node)
                            .desaturated(by: desaturation)
                            .opacity(opacity)
                        let rect = CGRect(x: p.x - drawRadius, y: p.y - drawRadius,
                                          width: drawRadius * 2, height: drawRadius * 2)

                        // Hover ring — soft halo under the fill so pointer
                        // users get the same "this is targetable" feedback
                        // touch users get via tap.
                        if hoveredNodeID == node.id {
                            let hoverR = drawRadius + 5
                            let hoverRect = CGRect(x: p.x - hoverR, y: p.y - hoverR,
                                                   width: hoverR * 2, height: hoverR * 2)
                            context.fill(Path(ellipseIn: hoverRect),
                                         with: .color(nodeColor(node).opacity(0.18)))
                            context.stroke(Path(ellipseIn: hoverRect),
                                           with: .color(.white.opacity(0.45)),
                                           lineWidth: 1)
                        }

                        // Hero image disc — only when zoomed in past the
                        // threshold AND a hero image is cached for this
                        // node. Replaces the flat fill; depth shadow
                        // still applied so the hero "lifts" with the
                        // node.
                        let useHero = scale > heroImageZoomThreshold
                            && heroImages[node.id] != nil
                        let drawNodeFill: (inout GraphicsContext) -> Void = { ctx in
                            if useHero, let img = heroImages[node.id] {
                                ctx.clipToLayer { layerCtx in
                                    layerCtx.fill(Path(ellipseIn: rect),
                                                  with: .color(.black))
                                }
                                ctx.draw(img, in: rect)
                            } else {
                                ctx.fill(Path(ellipseIn: rect), with: .color(fill))
                            }
                        }

                        // Foreground nodes (depth > 0.5) get a drop shadow that
                        // sharpens + darkens as they approach the present. The
                        // back half of the depth axis stays flat — those nodes
                        // read as "memory," not as objects on a surface.
                        if depth > 0.5 {
                            let t = (depth - 0.5) / 0.5
                            let shadowRadius = 8.0 - 6.0 * t       // 8 → 2
                            let shadowAlpha  = 0.18 + 0.32 * t     // 0.18 → 0.50
                            let shadowDy     = 1.0 + 2.5 * t       // 1 → 3.5
                            context.drawLayer { ctx in
                                ctx.addFilter(.shadow(
                                    color: .black.opacity(shadowAlpha),
                                    radius: shadowRadius,
                                    x: 0,
                                    y: shadowDy
                                ))
                                var inner = ctx
                                drawNodeFill(&inner)
                            }
                        } else {
                            var inner = context
                            drawNodeFill(&inner)
                        }

                        // Kick off a hero-image load if we haven't yet
                        // and the canvas is zoomed in enough to actually
                        // use it. Fire-and-forget; the cache mutation
                        // will trigger a redraw via @State.
                        if scale > heroImageZoomThreshold,
                           heroImages[node.id] == nil,
                           !heroLoadInFlight.contains(node.id),
                           node.attributes["hero"]?.isEmpty == false {
                            triggerHeroLoad(for: node)
                        }

                        // Pinned indicator — small white outline so the pin
                        // status is legible at a glance.
                        if pinnedPositions[node.id] != nil {
                            context.stroke(Path(ellipseIn: rect),
                                           with: .color(.white.opacity(inHighlight ? 0.95 : dimOpacity)),
                                           lineWidth: 1.5)
                        }

                        // Labels for background-pass nodes: only when
                        // zoomed in or part of an active highlight set.
                        let showLabel = inHighlight && (labelEnabled || hasSelection)
                        if showLabel {
                            let resolved = context.resolve(
                                Text(node.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(labelText.opacity(max(0.85, depthOpacityMul)))
                            )
                            drawLabelPill(
                                in: context,
                                text: resolved,
                                at: p,
                                fill: Color.black.opacity(0.40),
                                shadow: (color: .black.opacity(0.75),
                                         radius: 1.2, y: 1)
                            )
                        }
                    }

                    // Foreground pass — the idle-puffed node, drawn above
                    // every other background node so the spotlight reads.
                    // Hard drop shadow so it physically "lifts" off the canvas.
                    if let (node, p, baseRadius) = deferredAmbient {
                        let drawRadius = baseRadius * (1 + ambientPuff * 0.9)
                        let fill = nodeColor(node)
                        let rect = CGRect(x: p.x - drawRadius, y: p.y - drawRadius,
                                          width: drawRadius * 2, height: drawRadius * 2)
                        context.drawLayer { ctx in
                            ctx.addFilter(.shadow(
                                color: .black.opacity(0.55),
                                radius: 2.5,
                                x: 0,
                                y: 4
                            ))
                            ctx.fill(Path(ellipseIn: rect), with: .color(fill))
                        }

                        if pinnedPositions[node.id] != nil {
                            context.stroke(Path(ellipseIn: rect),
                                           with: .color(.white),
                                           lineWidth: 1.5)
                        }

                        let r = drawRadius + 2 + ambientPuff * 2
                        let ring = CGRect(x: p.x - r, y: p.y - r,
                                          width: r * 2, height: r * 2)
                        context.stroke(Path(ellipseIn: ring),
                                       with: .color(.accentColor.opacity(0.55 * ambientPuff)),
                                       lineWidth: 1.5)

                        let fontSize: CGFloat = 10 + ambientPuff * 3
                        let resolved = context.resolve(
                            Text(node.label)
                                .font(.system(size: fontSize).weight(.medium))
                                .foregroundStyle(labelText)
                        )
                        drawLabelPill(
                            in: context,
                            text: resolved,
                            at: p,
                            fill: Color.black.opacity(0.45),
                            shadow: (color: .black.opacity(0.8),
                                     radius: 1.6, y: 1.5)
                        )
                    }

                    // Second pass — the selected node, drawn last so it sits
                    // on top of every edge, neighbor, and label. Treatment:
                    //   1. soft breathing halo (stacked translucent rings)
                    //   2. core fill (the node itself, pulsed)
                    //   3. sparse orbital sparks (very subtle, slow)
                    //   4. label
                    if let (node, p, baseRadius) = deferredSelected {
                        let nodeRadius = baseRadius * (1 + selectionPulse)

                        // --- Glow halo ---------------------------------
                        // Four concentric translucent fills approximate a
                        // soft radial gradient without any shader work.
                        // A slow `breath` keeps the halo from feeling static.
                        let breath = 1.0 + 0.18 * sin(t * 1.3)
                        let halo: [(CGFloat, Double)] = [
                            (nodeRadius + 4  * CGFloat(breath), 0.42),
                            (nodeRadius + 10 * CGFloat(breath), 0.22),
                            (nodeRadius + 18 * CGFloat(breath), 0.10),
                            (nodeRadius + 30 * CGFloat(breath), 0.04),
                        ]
                        // Largest first so smaller rings paint on top.
                        for (r, alpha) in halo.reversed() {
                            let glowRect = CGRect(x: p.x - r, y: p.y - r,
                                                  width: r * 2, height: r * 2)
                            context.fill(Path(ellipseIn: glowRect),
                                         with: .color(selectionGold.opacity(alpha)))
                        }

                        // --- Core ------------------------------------
                        // Hardest shadow on the canvas — the selected node
                        // is conceptually "most foreground" and should
                        // physically pop above the soft glow halo.
                        let fill = nodeColor(node)
                        let rect = CGRect(x: p.x - nodeRadius, y: p.y - nodeRadius,
                                          width: nodeRadius * 2, height: nodeRadius * 2)
                        context.drawLayer { ctx in
                            ctx.addFilter(.shadow(
                                color: .black.opacity(0.6),
                                radius: 2,
                                x: 0,
                                y: 5
                            ))
                            ctx.fill(Path(ellipseIn: rect), with: .color(fill))
                        }

                        // --- Orbital sparks --------------------------
                        // Six small specks orbit the node at ~9 sec/turn,
                        // each with a slow pulse so the system feels alive
                        // without looking like a game effect.
                        let sparkCount = 6
                        let orbitBase = nodeRadius + 14
                        for i in 0..<sparkCount {
                            let baseAngle = Double(i) / Double(sparkCount) * .pi * 2
                            let angle = baseAngle + t * 0.7
                            let wobble = sin(t * 2.1 + Double(i)) * 1.2
                            let orbitR = orbitBase + CGFloat(wobble)
                            let sx = p.x + orbitR * CGFloat(cos(angle))
                            let sy = p.y + orbitR * CGFloat(sin(angle))
                            let pulse = 0.55 + 0.35 * sin(t * 1.7 + Double(i) * 0.9)
                            let sr: CGFloat = 1.4
                            let sparkRect = CGRect(x: sx - sr, y: sy - sr,
                                                   width: sr * 2, height: sr * 2)
                            context.fill(Path(ellipseIn: sparkRect),
                                         with: .color(selectionGold.opacity(pulse * 0.7)))
                        }

                        // --- Label ----------------------------------
                        let labelScale: CGFloat = 1 + selectionPulse
                        let resolved = context.resolve(
                            Text(node.label)
                                .font(.system(size: 11 * labelScale).weight(.semibold))
                                .foregroundStyle(labelText)
                        )
                        drawLabelPill(
                            in: context,
                            text: resolved,
                            at: p,
                            fill: selectionGold.opacity(0.32),
                            stroke: selectionGold.opacity(0.75),
                            shadow: (color: .black.opacity(0.85),
                                     radius: 2, y: 2)
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .background(
                // Deep indigo → near-black radial field. Echoes the app
                // icon's gradient so the runtime reads as the same world
                // the user tapped to enter.
                RadialGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.28),
                        Color(red: 0.02, green: 0.02, blue: 0.05)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.85
                )
                .ignoresSafeArea()
            )
            .background(
                MouseInputMonitor(
                    onScroll: { delta in
                        let factor = 1.0 + (delta * 0.0035)
                        let newScale = scale * factor
                        scale = max(minScale, min(maxScale, newScale))
                    },
                    onMiddleDrag: { dx, dy in
                        offset = CGSize(width: offset.width + dx,
                                        height: offset.height + dy)
                    }
                )
            )
            // Pinch wins when two fingers are detected — otherwise drag
            // (single-finger pan or node-drag) handles the gesture.
            // `.highPriorityGesture` is what makes pinch beat drag on
            // iPad; `.simultaneousGesture` alone wasn't enough — the
            // drag would still latch onto the first finger.
            .highPriorityGesture(pinchGesture())
            // `.simultaneousGesture` (instead of plain `.gesture`) so
            // pan doesn't have to outlast arbitration against the tap,
            // long-press, and contextMenu recognizers — that wait was
            // the residual iOS "delayed pan" feel even after the
            // minimumDistance drop to 1.
            .simultaneousGesture(nodeDragGesture(size: geo.size))
            .onTapGesture(coordinateSpace: .local) { point in
                handleTap(at: point, size: geo.size)
            }
            // Long-press on empty canvas → spatial node creation. The
            // press location is captured via a simultaneous zero-distance
            // drag because `LongPressGesture` alone doesn't expose its
            // location.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55, maximumDistance: 8)
                    .simultaneously(with: DragGesture(minimumDistance: 0,
                                                     coordinateSpace: .local))
                    .onEnded { value in
                        guard value.first == true,
                              let drag = value.second else { return }
                        if let nodeID = nodeAt(screenPoint: drag.startLocation,
                                               size: geo.size) {
                            // Long-press on a node → radial menu.
                            Haptics.tap(.medium)
                            onLongPressNode?(nodeID, drag.startLocation)
                            return
                        }
                        // Empty canvas → spatial new-node creation.
                        let world = worldPoint(at: drag.startLocation,
                                               size: geo.size)
                        Haptics.tap(.soft)
                        onLongPressEmptyWorld?(world)
                    }
            )
            .contextMenu { selectedNodeMenu() }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let hit = nodeAt(screenPoint: point, size: geo.size)
                    if hit != hoveredNodeID { hoveredNodeID = hit }
                case .ended:
                    if hoveredNodeID != nil { hoveredNodeID = nil }
                }
            }
            .onAppear {
                canvasSize = geo.size
                seedAtmosphereSpecks()
            }
            .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
        }
        .task(id: store.graph.nodes.count) {
            await rebuildLayoutPipeline()
        }
        .task { await runAmbientCycle() }
        .onChange(of: selectedNodeID) { _, newValue in
            if newValue != nil {
                // Match the time domain used inside the Canvas closure
                // (timeline.date mod 86400) so `elapsed = t - start` is sane.
                selectionPulseStart = Date().timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 86400)
                frameHighlightedSubnet()
                // Cancel any in-flight ambient puff so it doesn't fight
                // the user's deliberate selection.
                ambientHighlightID = nil
                ambientHighlightStart = nil
                Haptics.tap(.light)
            }
        }
        .onChange(of: pendingNewNode) { _, newValue in
            guard let pending = newValue else { return }
            consumePendingNewNode(pending)
        }
        .onChange(of: frameAllPulse) { _, _ in
            // Yield once so the canvasSize binding is current if the
            // pulse came from a window-resize transient. With a
            // selection we frame the highlighted subnet centered on
            // it; otherwise we fit the whole visible graph.
            Task { @MainActor in
                await Task.yield()
                if selectedNodeID != nil {
                    frameHighlightedSubnet()
                } else {
                    frameAllVisible()
                }
            }
        }
    }

    // MARK: - Idle / ambient animation

    /// Background loop that periodically picks a random node and puffs it
    /// when the user is idle (no selection). One puff at a time, spaced
    /// 3.5–6.5 seconds apart. Sleeps quietly during user interaction.
    private func runAmbientCycle() async {
        // Small initial delay so the first puff doesn't fire while the
        // layout is still settling.
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            let pause = Double.random(in: 3.5...6.5)
            try? await Task.sleep(for: .seconds(pause))
            if Task.isCancelled { break }

            // Only act when the user is idle and we have nodes to choose from.
            guard selectedNodeID == nil, !store.graph.nodes.isEmpty else { continue }

            // Pick a node, weighted toward higher-degree (more interesting)
            // nodes so the spotlight surfaces meaningful entries more often.
            let nodes = Array(store.graph.nodes.values)
            let chosen = pickWeightedNode(from: nodes) ?? nodes.randomElement()
            guard let id = chosen?.id, id != ambientHighlightID else { continue }

            ambientHighlightID = id
            ambientHighlightStart = Date().timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 86400)
        }
    }

    /// Generate a deterministic field of background specks once so they
    /// don't shimmer between redraws. Scattered across a wide world rect
    /// so panning reveals new specks rather than running out.
    private func seedAtmosphereSpecks() {
        guard atmosphereSpecks.isEmpty else { return }
        var rng = SplitMix64(seed: 0xC0FFEE_CAFE_BEEF)
        let count = 140
        let halfWidth: CGFloat = 4000
        let halfHeight: CGFloat = 3000
        atmosphereSpecks = (0..<count).map { _ in
            AtmosphereSpeck(
                x: CGFloat(rng.nextUnit() * 2 - 1) * halfWidth,
                y: CGFloat(rng.nextUnit() * 2 - 1) * halfHeight,
                radius: 0.6 + CGFloat(rng.nextUnit()) * 1.0,
                phase: rng.nextUnit() * 6.28318
            )
        }
    }

    /// Weighted random pick: prefer nodes with more connections.
    private func pickWeightedNode(from nodes: [Node]) -> Node? {
        let weights = nodes.map { 1 + (adjacency[$0.id]?.count ?? 0) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        let target = Int.random(in: 0..<total)
        var running = 0
        for (i, w) in weights.enumerated() {
            running += w
            if running > target { return nodes[i] }
        }
        return nodes.last
    }

    // MARK: - Spatial node-creation handoff

    /// Pin the new node at its spawn world point (or near the current
    /// selection / origin if no point was provided), select it, animate
    /// a frame onto it, and clear the pending binding.
    private func consumePendingNewNode(_ pending: PendingNewNode) {
        let spawn: CGPoint = {
            if let p = pending.worldPoint { return p }
            // No explicit point — prefer "near the current selection"
            // so a `+` press without a long-press still feels spatial.
            // Fall back to the world origin if nothing's selected.
            if let sel = selectedNodeID, sel != pending.id,
               let p = effectivePosition(for: sel) {
                return CGPoint(x: p.x + 90, y: p.y + 30)
            }
            return .zero
        }()
        pinnedPositions[pending.id] = spawn
        layout[pending.id] = spawn          // also seed the global layout
        selectedNodeID = pending.id
        persistLayout()
        // Defer the frame to the next runloop so the new node is in
        // `effectivePosition` before `frameHighlightedSubnet` reads it.
        Task { @MainActor in
            await Task.yield()
            frameHighlightedSubnet()
        }
        pendingNewNode = nil
    }

    // MARK: - Auto-framing

    /// Animate `scale` and `offset` so the currently highlighted set
    /// (selected node + 1-hop neighbors) fits the canvas with padding,
    /// with the selected node placed at the viewport center.
    /// Skipped if the layout or canvas size isn't ready yet.
    private func frameHighlightedSubnet() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let highlighted = highlightedNodeIDs()
        let points = highlighted.compactMap { effectivePosition(for: $0) }
        guard !points.isEmpty else { return }

        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        // Anchor the camera on the selected node so it lands dead-
        // center; fall back to bbox midpoint if (somehow) we don't
        // have a selection position.
        let centerWorld: CGPoint = {
            if let sel = selectedNodeID, let p = effectivePosition(for: sel) {
                return p
            }
            return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        }()
        // Symmetric extent around centerWorld — the largest distance
        // from center to any highlighted point, doubled. Ensures every
        // neighbor stays in-frame even though we're not bbox-centering.
        let halfWidthWorld  = max(centerWorld.x - minX, maxX - centerWorld.x)
        let halfHeightWorld = max(centerWorld.y - minY, maxY - centerWorld.y)
        // Floor the bbox so a singleton (no neighbors) doesn't try to zoom
        // to infinity, and pad the world rect to make room for node radii
        // and a little breathing space.
        let widthWorld  = max(halfWidthWorld * 2 + 80, 200)
        let heightWorld = max(halfHeightWorld * 2 + 80, 200)

        let chromePadding: CGFloat = 60  // top bar + inspector breathing room
        let availableWidth  = max(canvasSize.width  - chromePadding * 2, 200)
        let availableHeight = max(canvasSize.height - chromePadding * 2, 200)

        let candidate = min(availableWidth / widthWorld,
                            availableHeight / heightWorld)
        // Don't zoom past 2.2× (a singleton would otherwise become huge),
        // and don't zoom out below the user's current setting unless we
        // need to.
        let targetScale = max(0.4, min(candidate, 2.2))

        let targetOffset = CGSize(width: -centerWorld.x * targetScale,
                                  height: -centerWorld.y * targetScale)

        withAnimation(.easeInOut(duration: 0.55)) {
            scale = targetScale
            offset = targetOffset
            lastScaleValue = 1
        }
    }

    /// Animate scale + offset so every currently-visible node fits in
    /// the viewport with padding. Used by the top-bar Fit-to-view
    /// button and the auto-frame-on-load handler. When node counts are
    /// small, caps zoom at 2.2× so a cluster of three doesn't look
    /// like a wall of buttons.
    private func frameAllVisible() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
            Set(store.graph.nodes.values.filter(filter).map(\.id))
        }
        let candidateIDs: [String] = {
            if let visibleSet { return Array(visibleSet) }
            return Array(store.graph.nodes.keys)
        }()
        let points = candidateIDs.compactMap { effectivePosition(for: $0) }
        guard !points.isEmpty else { return }

        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let centerWorld = CGPoint(x: (minX + maxX) / 2,
                                  y: (minY + maxY) / 2)
        let widthWorld  = max(maxX - minX + 80, 200)
        let heightWorld = max(maxY - minY + 80, 200)

        let chromePadding: CGFloat = 80   // top bar + breathing room
        let availableWidth  = max(canvasSize.width  - chromePadding * 2, 200)
        let availableHeight = max(canvasSize.height - chromePadding * 2, 200)

        let candidate = min(availableWidth / widthWorld,
                            availableHeight / heightWorld)
        // Frame-all gets the same generous floor as direct manipulation,
        // capped above at 2.2× so a sparse cluster doesn't fill the
        // viewport with a wall of nodes.
        let targetScale = max(minScale, min(candidate, 2.2))
        let targetOffset = CGSize(width: -centerWorld.x * targetScale,
                                  height: -centerWorld.y * targetScale)

        withAnimation(.easeInOut(duration: 0.55)) {
            scale = targetScale
            offset = targetOffset
            lastScaleValue = 1
        }
    }

    // MARK: - Label pill

    /// Draw a resolved text label inside a capsule pill so titles read
    /// over the gradient and over other nodes. Pill + text share a single
    /// shadow layer for a unified "card lifted off the canvas" feel.
    private func drawLabelPill(
        in context: GraphicsContext,
        text resolved: GraphicsContext.ResolvedText,
        at center: CGPoint,
        fill: Color,
        stroke: Color? = nil,
        shadow: (color: Color, radius: CGFloat, y: CGFloat)
    ) {
        let textSize = resolved.measure(in: CGSize(width: 600, height: 100))
        let padH: CGFloat = 6
        let padV: CGFloat = 2
        let pillRect = CGRect(
            x: center.x - textSize.width / 2 - padH,
            y: center.y - textSize.height / 2 - padV,
            width: textSize.width + padH * 2,
            height: textSize.height + padV * 2
        )
        let pillPath = Path(
            roundedRect: pillRect,
            cornerRadius: pillRect.height / 2
        )
        context.drawLayer { ctx in
            ctx.addFilter(.shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: 0,
                y: shadow.y
            ))
            ctx.fill(pillPath, with: .color(fill))
            if let stroke {
                ctx.stroke(pillPath, with: .color(stroke), lineWidth: 1)
            }
            ctx.draw(resolved, at: center, anchor: .center)
        }
    }

    // MARK: - Layout pipeline (circular seed → background force-directed)

    private func rebuildLayoutPipeline() async {
        let snapshotNodes = Array(store.graph.nodes.values)
        let nodeIDs = snapshotNodes.map { $0.id }
        let edgePairs = store.graph.edges.map { ($0.sourceID, $0.targetID) }

        rebuildAdjacency()

        guard !nodeIDs.isEmpty else {
            layout = [:]
            return
        }

        // Try to restore a saved layout for the same node set. If every
        // current node has a saved position we skip FA2 entirely — the
        // user's persistent placements stay put across launches.
        if let persisted = LayoutPersistence.load() {
            let saved = persisted.cgPositions
            if Set(nodeIDs).isSubset(of: Set(saved.keys)) {
                layout = saved
                pinnedPositions = persisted.cgPinned
                scale = max(minScale, min(maxScale, CGFloat(persisted.scale)))
                offset = CGSize(width: persisted.offsetX, height: persisted.offsetY)
                layoutAlgorithm = .forceDirected
                return
            }
        }

        // 1. Cheap circular seed so something appears immediately.
        layout = makeCircularLayout(for: nodeIDs)
        layoutAlgorithm = .circular

        // 2. Background force-directed layout, swapped in once it converges.
        let solver = ForceDirectedLayout()
        let computed = await Task.detached(priority: .userInitiated) {
            solver.compute(nodeIDs: nodeIDs, edges: edgePairs)
        }.value

        // Bail if the graph has been replaced under us while we were thinking.
        guard store.graph.nodes.count == nodeIDs.count else { return }

        withAnimation(.easeInOut(duration: 0.6)) {
            layout = computed
            layoutAlgorithm = .forceDirected
        }
        persistLayout()
    }

    /// Snapshot current layout + view state and persist to disk.
    private func persistLayout() {
        var snapshot = PersistedLayout()
        snapshot.positions = layout.mapValues(PersistedLayout.Point.init)
        snapshot.pinned = pinnedPositions.mapValues(PersistedLayout.Point.init)
        snapshot.scale = Double(scale)
        snapshot.offsetX = Double(offset.width)
        snapshot.offsetY = Double(offset.height)
        Task.detached { LayoutPersistence.save(snapshot) }
    }

    private func makeCircularLayout(for ids: [String]) -> [String: CGPoint] {
        let count = max(ids.count, 1)
        let radius = CGFloat(280 + min(ids.count, 600) / 2)
        var new: [String: CGPoint] = [:]
        new.reserveCapacity(count)
        for (i, id) in ids.enumerated() {
            let angle = 2 * .pi * CGFloat(i) / CGFloat(count)
            new[id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        return new
    }

    // MARK: - Highlight set (N-hop BFS from the selection)

    private func highlightedNodeIDs() -> Set<String> {
        guard let seed = selectedNodeID else { return [] }
        var visited: Set<String> = [seed]
        var frontier: [String] = [seed]
        for _ in 0..<highlightDepth {
            var next: [String] = []
            for node in frontier {
                for neighbor in adjacency[node] ?? [] where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    next.append(neighbor)
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return visited
    }

    private func rebuildAdjacency() {
        var adj: [String: [String]] = [:]
        adj.reserveCapacity(store.graph.nodes.count)
        for edge in store.graph.edges {
            adj[edge.sourceID, default: []].append(edge.targetID)
            adj[edge.targetID, default: []].append(edge.sourceID)
        }
        adjacency = adj
        depthOrderedNodes = store.graph.nodes.values
            .sorted { $0.depth(in: store.config) < $1.depth(in: store.config) }
    }

    // MARK: - Node sizing by degree

    private let minNodeRadius: CGFloat = 10
    private let degreeRadiusFactor: CGFloat = 2.4   // multiplier on sqrt(degree)
    private let maxNodeRadius: CGFloat = 28

    private func radiusFor(nodeID: String) -> CGFloat {
        let degree = adjacency[nodeID]?.count ?? 0
        let scaled = minNodeRadius + degreeRadiusFactor * CGFloat(sqrt(Double(degree)))
        return min(scaled, maxNodeRadius)
    }


    // MARK: - Hit testing

    private func handleTap(at point: CGPoint, size: CGSize) {
        selectedNodeID = nodeAt(screenPoint: point, size: size)
        // Pulse-start is driven by `.onChange(of: selectedNodeID)` so it
        // fires for selections coming from the inspector too.
    }

    // MARK: - Edge batching

    private struct EdgeBatches {
        var dim: [EdgeStroke] = []
        var bright: [EdgeStroke] = []
    }

    /// Build the per-edge stroke list. Each edge carries the source
    /// node's color and the destination node's color so the render
    /// pass can stroke a linear gradient — making edges read as
    /// "type → type" transitions rather than uniform lines.
    private func edgeGroups(toScreen: (String, CGPoint, Double) -> CGPoint,
                            highlight: Set<String>,
                            hasSelection: Bool,
                            visibleSet: Set<String>?) -> EdgeBatches {
        var batches = EdgeBatches()

        for edge in store.graph.edges {
            let sourceID = edge.sourceID
            let targetID = edge.targetID

            if let visibleSet,
               !(visibleSet.contains(sourceID) && visibleSet.contains(targetID)) {
                continue
            }
            guard let a = effectivePosition(for: sourceID),
                  let b = effectivePosition(for: targetID),
                  let sourceNode = store.graph.nodes[sourceID],
                  let targetNode = store.graph.nodes[targetID] else { continue }
            let dA = sourceNode.depth(in: store.config)
            let dB = targetNode.depth(in: store.config)
            // Each endpoint inherits its node's effective opacity and
            // saturation — so an edge connecting a foreground "Star
            // Trek" to a deep-era "Star Trek franchise" ramps from
            // saturated/bright at the foreground end to muted/dim at
            // the background end, mirroring the nodes themselves.
            let sourceInHighlight = !hasSelection || highlight.contains(sourceID)
            let targetInHighlight = !hasSelection || highlight.contains(targetID)
            let sourceOpacity = (sourceInHighlight ? 1.0 : dimOpacity)
                * (0.55 + 0.45 * dA)
            let targetOpacity = (targetInHighlight ? 1.0 : dimOpacity)
                * (0.55 + 0.45 * dB)
            let sourceDesat = CGFloat(1.0 - dA) * 0.55
            let targetDesat = CGFloat(1.0 - dB) * 0.55
            let colorFrom = nodeColor(sourceNode)
                .desaturated(by: sourceDesat)
                .opacity(sourceOpacity)
            let colorTo = nodeColor(targetNode)
                .desaturated(by: targetDesat)
                .opacity(targetOpacity)
            // Seed the curve direction from the edge id so reciprocal
            // edges (A→B and B→A) bend opposite ways, and so the
            // same edge always bends the same way between frames.
            let seed = abs(edge.id.hashValue)
            let stroke = EdgeStroke(
                from: toScreen(sourceID, a, dA),
                to: toScreen(targetID, b, dB),
                colorFrom: colorFrom,
                colorTo: colorTo,
                curveSign: (seed & 1) == 0 ? 1 : -1
            )
            // Bright (both endpoints in the highlight subnet, or no
            // selection) draws on top so highlighted edges sit above
            // background traffic. Per-endpoint opacity already
            // handles the visual fade — the split is purely Z-order.
            let isBright = !hasSelection ||
                (highlight.contains(sourceID) && highlight.contains(targetID))
            if isBright {
                batches.bright.append(stroke)
            } else {
                batches.dim.append(stroke)
            }
        }
        return batches
    }

    /// Build the quadratic Bezier path for one edge. The control point
    /// is offset perpendicular to the line by a fraction of its length
    /// (so short edges curve subtly, long edges curve more), with the
    /// stable per-edge sign in `EdgeStroke.curveSign` choosing which
    /// side of the line the bend lands on.
    private func edgePath(_ stroke: EdgeStroke) -> Path {
        let dx = stroke.to.x - stroke.from.x
        let dy = stroke.to.y - stroke.from.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        // 12% of the line length keeps the curve readable without
        // overwhelming the layout.
        let bend = length * 0.12 * stroke.curveSign
        // Perpendicular unit vector → control point offset from midpoint.
        let perpX = -dy / length
        let perpY = dx / length
        let midX = (stroke.from.x + stroke.to.x) / 2
        let midY = (stroke.from.y + stroke.to.y) / 2
        let control = CGPoint(
            x: midX + perpX * bend,
            y: midY + perpY * bend
        )
        var path = Path()
        path.move(to: stroke.from)
        path.addQuadCurve(to: stroke.to, control: control)
        return path
    }

    // MARK: - Gestures

    private func pinchGesture() -> some Gesture {
        // `MagnifyGesture` (iOS 17 / macOS 14+) is the modern replacement
        // for `MagnificationGesture` — the older API still works but
        // touch-handling on iPad has been observed to lag behind it.
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastScaleValue
                let newScale = scale * delta
                scale = max(minScale, min(maxScale, newScale))
                lastScaleValue = value.magnification
            }
            .onEnded { _ in
                lastScaleValue = 1
            }
    }

    /// Drag gesture: if started on a node, drag that node; otherwise pan
    /// the canvas. On macOS, middle-mouse-drag also pans (via the
    /// MouseInputMonitor NSEvent layer) — both paths coexist. On iOS /
    /// iPadOS, this gesture is the only pan affordance.
    private func nodeDragGesture(size: CGSize) -> some Gesture {
        // `minimumDistance: 1` so pan engages on the first move event
        // instead of waiting for ~3pt of travel. The earlier 3pt floor
        // was the dominant cause of the iOS "delayed pan" feel —
        // arbitration against the tap / long-press recognizers held
        // the touch in suspense until the threshold cleared.
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if draggingNodeID == nil && panAnchor == nil {
                    if let hit = nodeAt(screenPoint: value.startLocation, size: size) {
                        // Started on a node → drag that node.
                        draggingNodeID = hit
                        selectedNodeID = hit
                    } else {
                        // Empty canvas → start a pan.
                        panAnchor = offset
                    }
                }
                if let id = draggingNodeID {
                    pinnedPositions[id] = worldPoint(at: value.location, size: size)
                } else if let anchor = panAnchor {
                    offset = CGSize(
                        width: anchor.width + value.translation.width,
                        height: anchor.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                if draggingNodeID != nil {
                    draggingNodeID = nil
                    persistLayout()
                }
                panAnchor = nil
            }
    }

    /// World-space position the canvas should render for a given node.
    /// Priority: pinned position → global layout.
    private func effectivePosition(for id: String) -> CGPoint? {
        if let pinned = pinnedPositions[id] { return pinned }
        return layout[id]
    }

    /// Convert a screen-space point inside the canvas to a world-space
    /// coordinate, undoing the current scale/offset/centre transform.
    private func worldPoint(at screen: CGPoint, size: CGSize) -> CGPoint {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: (screen.x - centre.x - offset.width) / scale,
                       y: (screen.y - centre.y - offset.height) / scale)
    }

    /// Hit-test a screen point and return the id of the topmost visible
    /// node under the cursor (respecting per-node radius + zoom-aware
    /// slack + the depth-based parallax offset).
    private func nodeAt(screenPoint: CGPoint, size: CGSize) -> String? {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let slack: CGFloat = 4
        let visibleSet: Set<String>? = visibleNodeFilter.map { filter in
            Set(store.graph.nodes.values.filter(filter).map(\.id))
        }
        // Walk front-to-back so the topmost (most foreground) node wins
        // when several stack near the cursor.
        var bestID: String?
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for node in depthOrderedNodes.reversed() {
            let id = node.id
            if let visibleSet, !visibleSet.contains(id) { continue }
            guard let p = effectivePosition(for: id) else { continue }
            let pf = CGFloat(0.55 + 0.45 * node.depth(in: store.config))
            // Same projection as toScreen, minus the per-frame drift
            // (drift wobble shouldn't disturb hit-testing).
            let sx = centre.x + p.x * scale + offset.width * pf
            let sy = centre.y + p.y * scale + offset.height * pf
            let d = hypot(sx - screenPoint.x, sy - screenPoint.y)
            let tapRadius = radiusFor(nodeID: id) + slack
            if d < tapRadius && d < bestDistance {
                bestDistance = d
                bestID = id
            }
        }
        return bestID
    }

    // MARK: - Styling

    private func nodeColor(_ node: Node) -> Color {
        if let spec = store.config.typeSpec(named: node.type) {
            return spec.color
        }
        return .white.opacity(0.9)
    }

    // MARK: - Hero image loading

    /// Fire-and-forget background load of a node's hero image. Resolves
    /// the filename relative to the node's directory, falls back to a
    /// vault-wide search. Caches the result in `heroImages` so the
    /// Canvas can draw it next frame.
    private func triggerHeroLoad(for node: Node) {
        guard let hero = node.attributes["hero"], !hero.isEmpty,
              let path = node.filePath else { return }
        heroLoadInFlight.insert(node.id)
        let nodeID = node.id
        let nodeDir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let vault = store.writableVaultURL
        Task.detached(priority: .utility) {
            let image = await Self.loadImage(named: hero, near: nodeDir, vault: vault)
            await MainActor.run {
                if let image { heroImages[nodeID] = image }
                heroLoadInFlight.remove(nodeID)
            }
        }
    }

    /// Resolve + decode an image file. Cross-platform: NSImage on Mac,
    /// UIImage on iOS. Returns a SwiftUI Image or nil.
    nonisolated private static func loadImage(named filename: String,
                                              near nodeDir: URL,
                                              vault: URL?) async -> Image? {
        let fm = FileManager.default
        var candidates: [URL] = [nodeDir.appendingPathComponent(filename)]
        if let vault {
            candidates.append(vault.appendingPathComponent(filename))
            // Recursive basename search — Obsidian doesn't require
            // a path if the filename is unique. `nextObject()` keeps
            // us out of the async-unavailable `makeIterator` path.
            let basename = (filename as NSString).lastPathComponent
            if let enumerator = fm.enumerator(
                at: vault,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                while let next = enumerator.nextObject() as? URL {
                    if next.lastPathComponent == basename {
                        candidates.append(next)
                        break
                    }
                }
            }
        }
        for url in candidates where fm.fileExists(atPath: url.path) {
            #if canImport(AppKit)
            if let ns = NSImage(contentsOf: url) {
                return Image(nsImage: ns)
            }
            #elseif canImport(UIKit)
            if let ui = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: ui)
            }
            #endif
        }
        return nil
    }

    // MARK: - Context menu (operates on currently selected node)

    @ViewBuilder
    private func selectedNodeMenu() -> some View {
        if let id = selectedNodeID, let node = store.graph.nodes[id] {
            Text(node.label)
            Button("Open note") { openSelectedNote(node) }
                .disabled(noteURL(for: node) == nil)
            Divider()
            if pinnedPositions[id] != nil {
                Button("Unpin") {
                    pinnedPositions.removeValue(forKey: id)
                    persistLayout()
                }
            } else {
                Button("Pin in place") {
                    if let p = layout[id] { pinnedPositions[id] = p }
                    persistLayout()
                }
            }
            if !pinnedPositions.isEmpty {
                Button("Unpin all (\(pinnedPositions.count))") {
                    pinnedPositions.removeAll()
                    persistLayout()
                }
            }
            Divider()
            Button("Clear selection") { selectedNodeID = nil }
        } else {
            Text("No node selected")
            if !pinnedPositions.isEmpty {
                Button("Unpin all (\(pinnedPositions.count))") {
                    pinnedPositions.removeAll()
                    persistLayout()
                }
            }
        }
    }

    /// Resolve the URL for a node's backing markdown file. `VaultLoader` sets
    /// `filePath` to an absolute path on disk — prefer that over the
    /// bundle-based lookup in `Node+File.swift`, which never resolves because
    /// we don't ship the vault as a bundle resource.
    private func noteURL(for node: Node) -> URL? {
        if let path = node.filePath { return URL(fileURLWithPath: path) }
        return node.file
    }

    private func openSelectedNote(_ node: Node) {
        if let url = noteURL(for: node) {
            _ = openFileURL(url)
        }
    }
}

// MARK: - Deterministic RNG for the atmosphere speck field

/// Tiny seeded RNG so the background star-field is identical every launch.
/// Not cryptographically anything — just stable + cheap.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Returns a Double in `[0, 1)`.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// MARK: - Mouse input monitor (macOS) — scroll wheel + middle-mouse drag

/// Invisible NSView that installs window-scoped `NSEvent` monitors for the
/// scroll wheel and middle-mouse drag. Returns `nil` from `hitTest(_:)` so
/// left-click events still reach SwiftUI underneath.
#if os(macOS)
private struct MouseInputMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onMiddleDrag: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MouseInputView()
        view.onScroll = onScroll
        view.onMiddleDrag = onMiddleDrag
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MouseInputView else { return }
        view.onScroll = onScroll
        view.onMiddleDrag = onMiddleDrag
    }

    private final class MouseInputView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onMiddleDrag: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?
        private var lastDragLocation: NSPoint?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                let mask: NSEvent.EventTypeMask = [
                    .scrollWheel,
                    .otherMouseDown, .otherMouseDragged, .otherMouseUp
                ]
                monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    guard let self,
                          let window = self.window,
                          event.window === window else { return event }
                    let pt = self.convert(event.locationInWindow, from: nil)
                    let inside = self.bounds.contains(pt)

                    switch event.type {
                    case .scrollWheel:
                        guard inside else { return event }
                        let dy = event.hasPreciseScrollingDeltas
                            ? event.scrollingDeltaY
                            : event.scrollingDeltaY * 10
                        self.onScroll?(dy)
                        return nil

                    case .otherMouseDown:
                        guard inside else { return event }
                        self.lastDragLocation = event.locationInWindow
                        return nil

                    case .otherMouseDragged:
                        guard let last = self.lastDragLocation else { return event }
                        let dx = event.locationInWindow.x - last.x
                        let dyWindow = event.locationInWindow.y - last.y
                        // NSWindow has y-up coords; SwiftUI offset uses y-down.
                        self.onMiddleDrag?(dx, -dyWindow)
                        self.lastDragLocation = event.locationInWindow
                        return nil

                    case .otherMouseUp:
                        guard self.lastDragLocation != nil else { return event }
                        self.lastDragLocation = nil
                        return nil

                    default:
                        return event
                    }
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#else
private struct MouseInputMonitor: View {
    let onScroll: (CGFloat) -> Void
    let onMiddleDrag: (CGFloat, CGFloat) -> Void
    var body: some View {
        // Explicitly opt out of hit-testing so we never steal a touch
        // from the canvas's pinch / drag / tap gestures on iOS.
        Color.clear.allowsHitTesting(false)
    }
}
#endif

// MARK: - Saturation helper

fileprivate extension Color {
    /// Returns a copy of this color with its saturation reduced by
    /// `amount` (0 = unchanged, 1 = fully desaturated to gray). Used by
    /// the depth-axis renderer to "wash out" background nodes so older
    /// eras read as memory rather than just dim.
    func desaturated(by amount: CGFloat) -> Color {
        guard amount > 0 else { return self }
        let clamped = max(0, min(1, amount))
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return self
        }
        return Color(hue: h, saturation: s * (1 - clamped), brightness: b, opacity: a)
        #elseif canImport(AppKit)
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: s * (1 - clamped), brightness: b, opacity: a)
        #else
        return self
        #endif
    }
}
