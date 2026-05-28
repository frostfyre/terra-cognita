import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Handles a folder dropped onto the canvas from Finder (macOS) or
/// Files (iPadOS with Stage Manager). Resolves the first
/// `public.file-url` provider it gets, verifies the URL points at a
/// directory, and hands it to the store like the picker would.
enum AtlasDropHandler {
    @MainActor
    static func handle(_ providers: [NSItemProvider], store: GraphStore) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            Task { @MainActor in
                store.load(from: url)
            }
        }
        return true
    }
}
