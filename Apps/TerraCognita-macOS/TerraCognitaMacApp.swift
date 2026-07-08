import SwiftUI
import AppKit
import TerraCognitaKit

@main
struct TerraCognitaMacApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.mainMenu?.item(at: 0)?.title = "Terra Cognita"
    }

    var body: some Scene {
        WindowGroup("Terra Cognita") {
            GraphView()
                .onAppear(perform: enterFullScreenOnFirstLaunch)
        }
    }

    /// One-shot fullscreen toggle on the first window after launch.
    /// Deferred to the next runloop so the NSWindow exists; guarded
    /// against re-entry if the user manually exits fullscreen and
    /// the view re-appears (e.g. after a sheet dismissal).
    private func enterFullScreenOnFirstLaunch() {
        guard !Self.hasEnteredFullScreen else { return }
        Self.hasEnteredFullScreen = true
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.title == "Terra Cognita" })
                            ?? NSApp.windows.first,
                  !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    private static var hasEnteredFullScreen = false
}
