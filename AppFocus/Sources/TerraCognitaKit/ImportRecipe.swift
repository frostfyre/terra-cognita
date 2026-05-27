import Foundation

/// Typed import specification — the deterministic counterpart to
/// natural-language import instructions. Per DESIGN.md:
///
/// > AI interprets. The importer executes deterministically.
///
/// The user types a sentence like "Import folder X. Texture nodes
/// orange, asset nodes blue. Link textures to assets by name
/// reference." → `RecipeInterpreter` parses it into an
/// `ImportRecipe` → user reviews / edits → `RecipeExecutor` walks
/// the source folder and materializes a vault.
struct ImportRecipe: Codable, Equatable {
    /// One-sentence summary of what the recipe does. Shown to the
    /// user during review.
    var summary: String
    /// Node-type rules — file patterns that materialize into typed
    /// nodes.
    var nodeRules: [NodeRule]
    /// Edge rules — strategies for linking the materialized nodes.
    var edgeRules: [EdgeRule]

    struct NodeRule: Codable, Equatable, Identifiable {
        var typeName: String     // becomes `type:` front-matter + subfolder
        var color: String        // SwiftUI color name or `#RRGGBB`
        var filePattern: String  // e.g. "*.png", "*.swift"
        var labelStrategy: LabelStrategy
        var id: String { typeName }
    }

    enum LabelStrategy: String, Codable, CaseIterable {
        case basename    // "foo.png" → "foo"
        case fullName    // "foo.png" → "foo.png"
    }

    struct EdgeRule: Codable, Equatable, Identifiable {
        var sourceType: String
        var targetType: String
        var strategy: EdgeStrategy
        var id: String { "\(sourceType)→\(targetType):\(strategy.rawValue)" }
    }

    enum EdgeStrategy: String, Codable, CaseIterable {
        /// Target node's label appears (case-insensitive substring) in
        /// the source file's contents.
        case nameReference
        /// Both files live in the same directory.
        case sameDirectory
        /// Basenames share a common prefix (at least 3 characters).
        case sharedPrefix

        var displayName: String {
            switch self {
            case .nameReference: return "Name reference"
            case .sameDirectory: return "Same directory"
            case .sharedPrefix:  return "Shared prefix"
            }
        }
    }
}
