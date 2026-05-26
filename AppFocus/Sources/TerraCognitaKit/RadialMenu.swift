import SwiftUI

/// A circular action wheel that appears around a node on long-press.
/// Each action is a satellite button arranged in an arc; tap one to
/// commit, tap outside (or hit the center) to cancel.
///
/// The menu lives as an overlay on the canvas, anchored to a screen
/// point. It's small, stateless across opens (no transitions to track),
/// and intentionally accepts only tap-to-commit — the drag-from-center
/// gesture popularized by autodesk-style apps doesn't quite map to
/// touch + pointer parity, so we stick with the simpler model.
struct RadialMenu: View {
    struct Action: Identifiable {
        let id: String
        let label: String
        let systemImage: String
        let tint: Color
        let onCommit: () -> Void
    }

    /// Screen-space center of the wheel.
    let center: CGPoint
    /// The actions to surface. Up to ~8 read well; beyond that the wheel
    /// gets cramped.
    let actions: [Action]
    /// Called when the user taps outside the wheel (or the center dot).
    let onCancel: () -> Void

    /// Pixel radius from center to each satellite button's center.
    private let radius: CGFloat = 78
    private let satelliteSize: CGFloat = 54

    var body: some View {
        ZStack {
            // Full-screen dimmer + tap-to-cancel layer.
            Color.black.opacity(0.30)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            // Center dot — visual anchor + a backup cancel target.
            Circle()
                .fill(.purple.opacity(0.55))
                .frame(width: 18, height: 18)
                .position(center)
                .onTapGesture { onCancel() }

            // Satellite buttons.
            ForEach(Array(actions.enumerated()), id: \.element.id) { i, action in
                let angle = angleFor(index: i, count: actions.count)
                let dx = cos(angle) * radius
                let dy = sin(angle) * radius
                Button {
                    Haptics.tap(.medium)
                    action.onCommit()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: action.systemImage)
                            .font(.callout.weight(.semibold))
                        Text(action.label)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(width: satelliteSize, height: satelliteSize)
                    .background(action.tint.opacity(0.95), in: Circle())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .position(x: center.x + dx, y: center.y + dy)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
    }

    /// Lay actions evenly around the wheel, with the first action at
    /// the top (12 o'clock) so the wheel reads symmetrically.
    private func angleFor(index: Int, count: Int) -> Double {
        let step = 2 * .pi / Double(max(count, 1))
        // -π/2 puts the first satellite at 12 o'clock (y-down screen).
        return -.pi / 2 + Double(index) * step
    }
}
