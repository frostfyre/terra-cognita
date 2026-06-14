import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Resolves + decodes a node's hero image. Shared by both renderers
/// (the Canvas draw pass and the Metal path's hero-image overlay) so
/// the lookup rules stay identical: filename relative to the node's
/// directory first, then the atlas root, then a recursive basename
/// search (Obsidian doesn't require a path when the filename is
/// unique).
enum HeroImageLoader {
    /// Cross-platform load: NSImage on Mac, UIImage on iOS. Returns
    /// a SwiftUI Image or nil.
    ///
    /// iOS sandboxes file access through security-scoped resources —
    /// the atlas URL came from the document picker / bookmark and
    /// must be bracketed before any file inside it is readable.
    /// macOS treats this as a no-op for non-sandboxed apps.
    nonisolated static func load(named filename: String,
                                 near nodeDir: URL,
                                 atlas: URL?) async -> Image? {
        let didStart = atlas?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didStart { atlas?.stopAccessingSecurityScopedResource() }
        }
        let fm = FileManager.default
        var candidates: [URL] = [nodeDir.appendingPathComponent(filename)]
        if let atlas {
            candidates.append(atlas.appendingPathComponent(filename))
            // Recursive basename search. `nextObject()` keeps us out
            // of the async-unavailable `makeIterator` path.
            let basename = (filename as NSString).lastPathComponent
            if let enumerator = fm.enumerator(
                at: atlas,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                while let next = enumerator.nextObject() as? URL {
                    if next.lastPathComponent == basename {
                        candidates.append(next)
                        break
                    }
                }
            }
        }
        for url in candidates where fm.fileExists(atPath: url.path) {
            #if canImport(AppKit)
            if let ns = NSImage(contentsOf: url) {
                return Image(nsImage: ns)
            }
            #elseif canImport(UIKit)
            if let ui = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: ui)
            }
            #endif
        }
        return nil
    }
}
