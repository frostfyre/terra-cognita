import SwiftUI

/// A circular action wheel that appears around an anchor point on
/// long-press. Each action is a satellite button arranged in an arc;
/// tap one to commit, tap outside (or the center) to cancel.
///
/// Supports **nesting**: an `Action` can carry `children: [Action]?`.
/// Tapping a wedge with children swaps the wheel to that sub-menu
/// (state lives internally so callers pass a single flat top-level
/// list). The center button becomes a back-arrow + parent label while
/// inside a sub-menu; otherwise it stays a "cancel" target.
///
/// The wheel lives as an overlay on the canvas, anchored to a screen
/// point. Small, transitions only between menu levels.
struct RadialMenu: View {
    struct Action: Identifiable {
        let id: String
        let label: String
        let systemImage: String
        let tint: Color
        /// `true` shows a small ✓ badge over the wedge, for toggle
        /// state (e.g., No-overlap currently on). Optional.
        let isChecked: Bool
        /// Either a terminal handler OR a sub-menu of actions. Set
        /// `children` non-nil for nesting; `onCommit` is ignored when
        /// children are present.
        let onCommit: () -> Void
        let children: [Action]?

        init(id: String,
             label: String,
             systemImage: String,
             tint: Color = .accentColor,
             isChecked: Bool = false,
             children: [Action]? = nil,
             onCommit: @escaping () -> Void = {}) {
            self.id = id
            self.label = label
            self.systemImage = systemImage
            self.tint = tint
            self.isChecked = isChecked
            self.children = children
            self.onCommit = onCommit
        }

        var hasChildren: Bool { (children?.isEmpty == false) }
    }

    /// Screen-space center of the wheel.
    let center: CGPoint
    /// Top-level actions. Sub-menus are reached by tapping a wedge
    /// with non-nil `children`.
    let actions: [Action]
    /// Called when the user taps outside the wheel, OR taps the
    /// center while at the top level. Tapping center inside a
    /// sub-menu pops back to the parent instead.
    let onCancel: () -> Void

    /// Pixel radius from center to each satellite button's center.
    private let radius: CGFloat = 86
    private let satelliteSize: CGFloat = 56

    /// Breadcrumb stack of menu levels we've descended into. Each
    /// entry stores the **children** of the wedge we just tapped (so
    /// they render here) plus that wedge's label (so the center
    /// button can show a back-arrow + name). Storing children
    /// directly on the crumb supports arbitrarily deep nesting —
    /// popping just removes the top crumb and `visibleActions`
    /// falls back to the next level (or root `actions`).
    @State private var crumbs: [Crumb] = []

    /// Drives the open-bloom animation: satellites start clustered
    /// at `center` with zero radius, then spring outward to their
    /// final positions on `onAppear`. Also scales the per-satellite
    /// visual size + fades them in. Flipped to false during dismiss
    /// (handled by the parent's transition) so the view collapses
    /// before unmount.
    @State private var bloomed: Bool = false

    private struct Crumb: Equatable {
        let label: String
        let children: [Action]

        static func == (lhs: Crumb, rhs: Crumb) -> Bool {
            lhs.label == rhs.label &&
            lhs.children.map(\.id) == rhs.children.map(\.id)
        }
    }

    private var atRoot: Bool { crumbs.isEmpty }

    var body: some View {
        // Bloom factor: 0 when closed (satellites stacked at center,
        // shrunk + invisible), 1 when open. Drives radius, scale, and
        // opacity for both the center button and each satellite.
        let bloom: CGFloat = bloomed ? 1.0 : 0.0
        ZStack {
            // Full-screen dimmer + tap-to-cancel layer. Fades in with
            // the wheel so the screen doesn't darken before the
            // satellites have visibly appeared.
            Color.black.opacity(0.30 * Double(bloom))
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            // Center button — cancel at root, back-arrow inside a sub-menu.
            centerButton
                .scaleEffect(0.5 + 0.5 * bloom)
                .opacity(Double(bloom))

            // Satellite buttons for the current menu level. Each one
            // starts stacked at `center` (effective radius = 0) and
            // springs outward to its final ring position.
            ForEach(Array(visibleActions.enumerated()), id: \.element.id) { i, action in
                let angle = angleFor(index: i, count: visibleActions.count)
                let dx = cos(angle) * radius * bloom
                let dy = sin(angle) * radius * bloom
                satellite(action)
                    .scaleEffect(0.4 + 0.6 * bloom)
                    .opacity(Double(bloom))
                    .position(x: center.x + dx, y: center.y + dy)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Spring with a touch of overshoot so the wheel feels
            // like it pops out of the user's finger.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                bloomed = true
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78),
                   value: crumbs.count)
    }

    /// The list of actions to display right now. When inside a sub-
    /// menu, this is the child list stored on the top crumb; at
    /// root, it's the top-level `actions`.
    private var visibleActions: [Action] {
        crumbs.last?.children ?? actions
    }

    // MARK: - Center button

    @ViewBuilder
    private var centerButton: some View {
        if atRoot {
            Circle()
                .fill(.purple.opacity(0.55))
                .frame(width: 22, height: 22)
                .position(center)
                .onTapGesture {
                    // `onCancel` is already wrapped in withAnimation
                    // by the parent for the radialTarget = nil path.
                    onCancel()
                }
        } else {
            VStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.callout.weight(.semibold))
                Text(crumbs.last?.label ?? "")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: satelliteSize, height: satelliteSize)
            .background(Color.purple.opacity(0.85), in: Circle())
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .position(center)
            .onTapGesture { popLevel() }
        }
    }

    // MARK: - Satellite

    @ViewBuilder
    private func satellite(_ action: Action) -> some View {
        Button {
            Haptics.tap(.medium)
            if action.hasChildren, let children = action.children {
                pushLevel(label: action.label, children: children)
            } else {
                // Wrap the terminal commit in an animation block so
                // the parent's `radialTarget = nil` (typically set
                // inside `onCommit`) triggers the wheel's collapse
                // transition.
                withAnimation(.easeOut(duration: 0.18)) {
                    action.onCommit()
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
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

                // Checkmark badge for toggle-state wedges.
                if action.isChecked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white, Color.green)
                        .offset(x: 4, y: -4)
                }
                // Sub-menu hint — small chevron in the lower-right.
                if action.hasChildren {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white, action.tint.opacity(0.65))
                        .offset(x: satelliteSize - 18, y: satelliteSize - 18)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private func pushLevel(label: String, children: [Action]) {
        crumbs.append(Crumb(label: label, children: children))
    }

    private func popLevel() {
        guard !crumbs.isEmpty else { return }
        crumbs.removeLast()
    }

    /// Lay actions evenly around the wheel, with the first action at
    /// the top (12 o'clock) so the wheel reads symmetrically.
    private func angleFor(index: Int, count: Int) -> Double {
        let step = 2 * .pi / Double(max(count, 1))
        // -π/2 puts the first satellite at 12 o'clock (y-down screen).
        return -.pi / 2 + Double(index) * step
    }
}
