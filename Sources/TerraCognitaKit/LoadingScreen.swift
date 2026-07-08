import SwiftUI

/// Full-screen loading surface shown from app launch until the atlas
/// has loaded *and* the canvas has laid out / framed. Deep blue
/// gradient with the Terra Cognita signature glyph (selected node +
/// orbital sparks) and the rotating cartographer caption.
///
/// Mounted in `GraphView.body` above `canvasStack`, present while
/// `store.loadingCaption != nil`, fading via `.transition(.opacity)`
/// driven by `GraphStore.finishLoadingPresentation`'s 2 s ease-out.
struct LoadingScreen: View {
    let caption: String

    /// Shared deep-midnight value used by the LoadingScreen gradient
    /// top stop and `canvasStack`'s root background. Painting the
    /// same color underneath the whole view tree guarantees no
    /// white-substrate flash between the platform launch surface
    /// (iOS LaunchBackground colorset on iOS, NSWindow default on
    /// macOS) and SwiftUI's first body render. Match this in
    /// `Apps/TerraCognita-iOS/Assets.xcassets/LaunchBackground.colorset`
    /// so iOS's launch screen color is identical too.
    static let substrate = Color(red: 0.04, green: 0.06, blue: 0.16)
    static let substrateBottom = Color(red: 0.09, green: 0.12, blue: 0.30)

    /// Flipped from false → true after the first dismissal of the
    /// loading screen. Drives whether macOS shows the TerraCognitaLaunch
    /// splash artwork (cold-start only) or the standard glyph (atlas
    /// switches / reloads mid-session). iOS already gets the splash
    /// via its native UILaunchScreen, so the iOS path never reads
    /// this — it always renders the glyph.
    private static var hasShownInitialLaunch = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.substrate, Self.substrateBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // macOS has no native UILaunchScreen, so the TerraCognitaLaunch
            // artwork (a landscape composition with the portrait piece
            // centered over an extended blurred bg) carries the cold-start
            // surface here, rendered full-bleed. Mid-session atlas
            // switches drop back to the glyph + caption — the splash is a
            // launch moment, not a regular loading affordance. iOS always
            // shows the glyph; its native UILaunchScreen already covered
            // the cold-start splash before this view mounted.
            #if os(macOS)
            if !Self.hasShownInitialLaunch {
                Image("TerraCognitaLaunch")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            #endif

            VStack(spacing: 36) {
                Spacer()
                #if os(macOS)
                if Self.hasShownInitialLaunch {
                    LoadingGlyph()
                        .frame(width: 140, height: 140)
                }
                #else
                LoadingGlyph()
                    .frame(width: 140, height: 140)
                #endif
                Text(caption)
                    .font(.title3.weight(.light))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, splashBottomPadding)
                    .id(caption)
                    .transition(.opacity)
                #if os(macOS)
                if Self.hasShownInitialLaunch { Spacer() }
                #else
                Spacer()
                #endif
            }
            .animation(.easeInOut(duration: 0.4), value: caption)
        }
        .onDisappear {
            // First dismissal = cold-start splash has done its job. Any
            // subsequent LoadingScreen (atlas switch) renders the glyph.
            Self.hasShownInitialLaunch = true
        }
    }

    /// More breathing room beneath the caption on the cold-start splash
    /// (caption sits over the artwork's "WHERE IDEAS MEET …" tagline area),
    /// standard padding once we're back to the glyph layout.
    private var splashBottomPadding: CGFloat {
        #if os(macOS)
        Self.hasShownInitialLaunch ? 0 : 60
        #else
        0
        #endif
    }
}

/// Signature glyph — a gold core node with six orbital sparks,
/// matching the canvas's idle animation for the currently-selected
/// node. Drives itself off a 20 Hz `TimelineView` so the orbit is
/// smooth without the host having to drive state.
private struct LoadingGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 86400)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let coreRadius = size.width * 0.18
                let orbitRadius = coreRadius + size.width * 0.18
                let gold = Color(red: 0.96, green: 0.82, blue: 0.46)

                // Subtle outer glow so the core reads as luminous
                // against the deep gradient, not flat.
                let glowRadius = coreRadius + size.width * 0.10
                let glowRect = CGRect(x: centre.x - glowRadius,
                                      y: centre.y - glowRadius,
                                      width: glowRadius * 2,
                                      height: glowRadius * 2)
                ctx.fill(Path(ellipseIn: glowRect),
                         with: .color(gold.opacity(0.10)))

                // Core node — gentle scale breathe.
                let pulse = 1.0 + 0.05 * sin(t * 1.3)
                let r = coreRadius * pulse
                let coreRect = CGRect(x: centre.x - r,
                                      y: centre.y - r,
                                      width: r * 2,
                                      height: r * 2)
                ctx.fill(Path(ellipseIn: coreRect), with: .color(gold))

                // Six orbital sparks — same recipe as the canvas
                // selection animation so the launch screen and the
                // in-app affordance speak the same visual language.
                let sparkCount = 6
                for i in 0..<sparkCount {
                    let baseAngle = Double(i) / Double(sparkCount) * .pi * 2
                    let angle = baseAngle + t * 0.7
                    let wobble = sin(t * 2.1 + Double(i)) * 3
                    let orbitR = orbitRadius + CGFloat(wobble)
                    let sx = centre.x + orbitR * CGFloat(cos(angle))
                    let sy = centre.y + orbitR * CGFloat(sin(angle))
                    let sparkPulse = 0.55 + 0.35 * sin(t * 1.7 + Double(i) * 0.9)
                    let sr: CGFloat = 4.5
                    let sparkRect = CGRect(x: sx - sr,
                                           y: sy - sr,
                                           width: sr * 2,
                                           height: sr * 2)
                    ctx.fill(Path(ellipseIn: sparkRect),
                             with: .color(gold.opacity(sparkPulse * 0.9)))
                }
            }
        }
    }
}
