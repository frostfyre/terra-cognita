import SwiftUI

/// Gate for both renderers' fps readouts. They are development
/// instruments, not product UI: always on in DEBUG builds (the
/// `swift run` dev loop), hidden in release unless explicitly
/// enabled with `defaults write <bundle-id> showFPSReadout -bool YES`
/// — so a TestFlight perf session can still turn them on.
enum FPSReadout {
    static var enabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "showFPSReadout")
        #endif
    }
}

/// FPS readout for the SwiftUI Canvas path. Mirrors the Metal "Pro"
/// renderer's `FPSOverlay` so the two renderers can be compared
/// without flipping mental models.
///
/// Measures "SwiftUI runloop responsiveness" — `TimelineView(.animation)`
/// is supposed to fire at display refresh, but when the main thread
/// is choked by heavy Canvas body re-evaluations (the 15K-node
/// pathological case) tick deliveries get delayed and the effective
/// rate drops. Not a literal "Canvas draw rate" measurement, but a
/// useful proxy for "does the UI feel snappy."
struct CanvasFPSOverlay: View {
    @State private var fps: Double = 0
    @State private var frameCount: Int = 0
    @State private var lastSampleTime: TimeInterval = CACurrentMediaTime()

    var body: some View {
        TimelineView(.animation) { timeline in
            VStack {
                Spacer()
                HStack {
                    Text(String(format: "%.0f fps", fps))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(fpsColor(fps))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                    Spacer()
                }
            }
            .onChange(of: timeline.date) { _, newDate in
                let now = newDate.timeIntervalSinceReferenceDate
                frameCount += 1
                let elapsed = now - lastSampleTime
                if elapsed >= 0.5 {
                    fps = Double(frameCount) / elapsed
                    frameCount = 0
                    lastSampleTime = now
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 60 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }
}
