import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Cross-platform haptic feedback. No-op on macOS; light/medium impact
/// on iOS. Calls are safe from any thread — the iOS path hops to the
/// main actor internally.
enum Haptics {
    enum Strength {
        case light, medium, soft
    }

    static func tap(_ strength: Strength = .light) {
        #if canImport(UIKit)
        Task { @MainActor in
            let style: UIImpactFeedbackGenerator.FeedbackStyle = {
                switch strength {
                case .light:  return .light
                case .medium: return .medium
                case .soft:   return .soft
                }
            }()
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
        #endif
    }
}
