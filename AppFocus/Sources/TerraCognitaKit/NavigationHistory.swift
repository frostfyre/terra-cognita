import Foundation
import SwiftUI

/// Browser-style back/forward stack for the canvas's exploration state.
///
/// A "state" is the current `selectedNodeID`. The stack
/// records meaningful navigation events so the user can `⌘[` to retreat
/// and `⌘]` to re-advance. Camera state (scale / offset / lens) is
/// intentionally not tracked — back/forward should restore *where you
/// were looking at*, not clobber a manual pan/zoom.
///
/// In-session only — the stack resets on relaunch.
@MainActor
final class NavigationHistory: ObservableObject {
    struct State: Equatable {
        var selectedNodeID: String?
    }

    @Published private(set) var back: [State] = []
    @Published private(set) var forward: [State] = []

    /// Set to `true` while we drive a state change from inside this
    /// class (goBack / goForward). Lets the host's `.onChange` skip
    /// the recording loop.
    @Published var suppressRecording: Bool = false

    private static let depthCap = 64

    var canGoBack: Bool    { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// Record a new state. Drops consecutive duplicates; clears the
    /// forward stack (any new exploration invalidates the redo path).
    func record(_ next: State, previous: State) {
        if next == previous { return }
        // Don't push two identical entries in a row.
        if back.last == previous { /* already recorded */ }
        else { back.append(previous) }
        if back.count > Self.depthCap {
            back.removeFirst(back.count - Self.depthCap)
        }
        forward.removeAll()
    }

    func goBack(from current: State) -> State? {
        guard let previous = back.popLast() else { return nil }
        forward.append(current)
        if forward.count > Self.depthCap {
            forward.removeFirst(forward.count - Self.depthCap)
        }
        return previous
    }

    func goForward(from current: State) -> State? {
        guard let next = forward.popLast() else { return nil }
        back.append(current)
        if back.count > Self.depthCap {
            back.removeFirst(back.count - Self.depthCap)
        }
        return next
    }

    func clear() {
        back.removeAll()
        forward.removeAll()
    }
}
