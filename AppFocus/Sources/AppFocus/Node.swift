import Foundation

/// Represents a single node in the heritage graph.
struct Node: Identifiable, Equatable, Hashable {
    /// The unique identifier of the node, typically the name or title.
    let id: String

    /// The human-readable label for the node.
    let label: String

    /// Attributes provide detailed information about the node.
    /// These correspond to columns/fields from imports (e.g., GEXF) or YAML front matter.
    var attributes: [String: String] = [:]

    /// The relative path to the corresponding Markdown file from the vault, if any.
    var filePath: String?

    /// Cached content of the corresponding Markdown file from the vault, if loaded.
    var markdownContent: String?

    // MARK: - Common derived attributes for convenience

    var type: String? { attributes["type"] }
    var era: String? { attributes["era"] }
    var folder: String? { attributes["folder"] }

    static func == (lhs: Node, rhs: Node) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
