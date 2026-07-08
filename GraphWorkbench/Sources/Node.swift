// Deprecated duplicate of Node. See canonical implementation in Node.swift
#if false
import Foundation

/// Represents a single node in the heritage graph.
struct Node: Identifiable, Equatable {
    /// The unique identifier of the node, typically the name or title.
    let id: String
    /// The human-readable label for the node.
    let label: String
    /// Attributes provide detailed information about the node.
    let attributes: [String: String]
    /// The content of the corresponding Markdown file from the Obsidian vault.
    var markdownContent: String?

    // MARK: - Computed Properties for easier access
    var type: String? { attributes["type"] }
    var tier: String? { attributes["tier"] }
    var primaryMedium: String? { attributes["primary_medium"] }
    var era: String? { attributes["era"] }
    var peakEra: String? { attributes["peak-era"] }
    var sensitivity: String? { attributes["sensitivity"] }
    var status: String? { attributes["status"] }
    var folder: String? { attributes["folder"] }

    static func == (lhs: Node, rhs: Node) -> Bool { lhs.id == rhs.id }
}
#endif
