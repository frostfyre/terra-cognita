import SwiftUI
import UIKit
import TerraCognitaKit

@main
struct TerraCognitaIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            GraphView()
        }
    }
}

/// Bridges UIKit's launch lifecycle so we can paint the hosting
/// controller's view background before SwiftUI's first render. The
/// `UIWindow.appearance` proxy alone doesn't cover the
/// `UIHostingController.view` that SwiftUI inserts between the
/// window and the scene content — that's the layer that briefly
/// showed white. Setting it directly via the scene-connect
/// notification eliminates the flash.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Same RGB as `LoadingScreen.substrate` and the iOS launch
    /// storyboard colorset, so every layer in the launch sandwich
    /// (launch screen, UIWindow, hosting view, SwiftUI substrate)
    /// is the same deep midnight.
    static let substrate = UIColor(
        red: 0.04, green: 0.06, blue: 0.16, alpha: 1.0
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Belt — set the window appearance proxy before any window
        // is constructed.
        UIWindow.appearance().backgroundColor = AppDelegate.substrate

        // Suspenders — as each scene connects, walk its windows and
        // tint both the window and the root view controller's view
        // (the SwiftUI hosting controller) directly. SwiftUI owns
        // the scene delegate when using `WindowGroup`, but
        // `UIScene.willConnectNotification` fires regardless, and
        // by the time we deliver onto the main queue the
        // rootViewController.view is ready to be styled.
        NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification,
            object: nil,
            queue: .main
        ) { notification in
            // Already on the main queue (queue: .main above), so
            // touch UIKit state directly. No async hop — that would
            // both invite a data-race warning and let the white frame
            // through.
            guard let windowScene = notification.object as? UIWindowScene
            else { return }
            for window in windowScene.windows {
                window.backgroundColor = AppDelegate.substrate
                window.rootViewController?.view.backgroundColor =
                    AppDelegate.substrate
            }
        }
        return true
    }
}
