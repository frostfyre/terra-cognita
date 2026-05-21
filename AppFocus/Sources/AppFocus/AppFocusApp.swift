import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct AppFocusApp: App {
    init() {
        #if os(macOS)
        // `swift run` produces a bare binary with no Info.plist, so the
        // process registers as a background-only app and no window appears.
        // Promote it to a regular foreground GUI app on launch.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            GraphView()
        }
    }
}

