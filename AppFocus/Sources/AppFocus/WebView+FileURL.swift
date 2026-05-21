import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Opens a file URL using the appropriate platform API.
/// Some call sites may have used an incorrect parameter label (url: vs fileURL:).
/// Use this helper to avoid signature mismatches and handle platform differences.
@discardableResult
public func openFileURL(_ fileURL: URL) -> Bool {
    #if os(macOS)
    return NSWorkspace.shared.open(fileURL)
    #else
    UIApplication.shared.open(fileURL, options: [:], completionHandler: nil)
    return true
    #endif
}
