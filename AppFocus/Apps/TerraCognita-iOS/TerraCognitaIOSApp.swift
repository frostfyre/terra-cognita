import SwiftUI
import UIKit
import TerraCognitaKit

@main
struct TerraCognitaIOSApp: App {
    init() {
        // Paint the UIWindow background to match the LoadingScreen's
        // gradient top *before* SwiftUI gets a chance to render. The
        // launch storyboard hands off to a brand-new UIWindow whose
        // default `.white` background otherwise flashes through for
        // a frame between launch screen end and the SwiftUI scene's
        // first paint. With the appearance proxy set here, the
        // window is dark from the moment iOS instantiates it.
        UIWindow.appearance().backgroundColor = UIColor(
            red: 0.04, green: 0.06, blue: 0.16, alpha: 1.0
        )
    }

    var body: some Scene {
        WindowGroup {
            GraphView()
        }
    }
}
