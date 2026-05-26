import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Opens a file URL using the appropriate platform API.
/// `UIApplication.shared` is `@MainActor` on iOS 18+, so this is too.
@discardableResult
@MainActor
public func openFileURL(_ fileURL: URL) -> Bool {
    #if os(macOS)
    return NSWorkspace.shared.open(fileURL)
    #else
    UIApplication.shared.open(fileURL, options: [:], completionHandler: nil)
    return true
    #endif
}
