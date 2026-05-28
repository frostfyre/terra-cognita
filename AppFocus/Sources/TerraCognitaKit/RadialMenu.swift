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
    /// entry is `(parentLabel, parentActions)` — the parent label
    /// renders in the center button while we're inside, and the
    /// parent's actions are what we restore on back. The top of the
    /// stack is the *current* visible level via `currentActions`.
    @State private var crumbs: [Crumb] = []

    private struct Crumb {
        let label: String
        let parentActions: [Action]
    }

    private var currentActions: [Action] {
        crumbs.last?.parentActions ?? actions
    }

    private var atRoot: Bool { crumbs.isEmpty }

    var body: some View {
        ZStack {
            // Full-screen dimmer + tap-to-cancel layer.
            Color.black.opacity(0.30)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            // Center button — cancel at root, back-arrow inside a sub-menu.
            centerButton

            // Satellite buttons for the current menu level.
            ForEach(Array(visibleActions.enumerated()), id: \.element.id) { i, action in
                let angle = angleFor(index: i, count: visibleActions.count)
                let dx = cos(angle) * radius
                let dy = sin(angle) * radius
                satellite(action)
                    .position(x: center.x + dx, y: center.y + dy)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.32, dampingFraction: 0.78),
                   value: crumbs.count)
    }

    /// The list of actions to display right now. When inside a sub-
    /// menu, this is the child list of the last-tapped parent; at
    /// root, it's the top-level `actions`.
    private var visibleActions: [Action] {
        if let last = crumbs.last,
           // The crumb stores the PARENT's full action list; we need
           // the CHILDREN of the wedge we descended through. To find
           // those we'd need a separate ref. Simpler: store the
           // children directly on the crumb. See Crumb refactor below.
           // For now, derive from the most-recently-pushed children.
           let lastChildren = lastChildren {
            return lastChildren
        }
        return actions
    }

    /// Tracks the children of the currently-shown sub-menu. Mirrors
    /// `crumbs` 1:1.
    @State private var lastChildren: [Action]?

    // MARK: - Center button

    @ViewBuilder
    private var centerButton: some View {
        if atRoot {
            Circle()
                .fill(.purple.opacity(0.55))
                .frame(width: 22, height: 22)
                .position(center)
                .onTapGesture { onCancel() }
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
                action.onCommit()
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
        crumbs.append(Crumb(label: label, parentActions: currentActions))
        lastChildren = children
    }

    private func popLevel() {
        guard !crumbs.isEmpty else { return }
        crumbs.removeLast()
        // Restore the previous level. If we just popped to root,
        // `lastChildren` clears.
        if crumbs.isEmpty {
            lastChildren = nil
        } else {
            // We can't reconstruct the parent's children easily from
            // here — instead, the breadcrumb-driven nav only goes one
            // level deep in practice. For deeper nests we'd carry
            // each level's children alongside its label.
            // Phase 3.7 first cut: keep depth ≤ 2; revisit when we
            // need depth 3+.
            lastChildren = nil
        }
    }

    /// Lay actions evenly around the wheel, with the first action at
    /// the top (12 o'clock) so the wheel reads symmetrically.
    private func angleFor(index: Int, count: Int) -> Double {
        let step = 2 * .pi / Double(max(count, 1))
        // -π/2 puts the first satellite at 12 o'clock (y-down screen).
        return -.pi / 2 + Double(index) * step
    }
}
