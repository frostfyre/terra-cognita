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
        // Set a friendly window/menu name for the running app.
        NSApplication.shared.mainMenu?.item(at: 0)?.title = "Terra Cognita"
        #endif
    }

    var body: some Scene {
        WindowGroup("Terra Cognita") {
            GraphView()
        }
    }
}

