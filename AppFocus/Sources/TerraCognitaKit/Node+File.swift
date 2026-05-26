import Foundation

// Provides a best-effort mapping from a Node to a local Markdown file bundled with the app.
extension Node {
    /// Attempts to locate a Markdown file for this node in the main bundle.
    /// Tries `<id>.md` first, then `<label>.md`.
    public var file: URL? {
        // Try by id first
        if let byID = Bundle.main.url(forResource: self.id, withExtension: "md") {
            return byID
        }
        // Fall back to label-based resource (allowing spaces and punctuation as-is)
        if let byLabel = Bundle.main.url(forResource: self.label, withExtension: "md") {
            return byLabel
        }
        return nil
    }
}
