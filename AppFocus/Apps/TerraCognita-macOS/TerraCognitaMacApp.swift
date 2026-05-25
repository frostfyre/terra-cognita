import SwiftUI
import AppKit
import AppFocusKit

@main
struct TerraCognitaMacApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.mainMenu?.item(at: 0)?.title = "Terra Cognita"
    }

    var body: some Scene {
        WindowGroup("Terra Cognita") {
            GraphView()
        }
    }
}
