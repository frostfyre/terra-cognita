import Foundation

/// Represents a directed edge between two nodes in the heritage graph.
struct Edge: Identifiable, Equatable, Hashable {
    /// A unique identifier for the edge.
    let id: String

    /// The identifier of the source node.
    let sourceID: String

    /// The identifier of the target node.
    let targetID: String

    /// The type of relationship (e.g., "influenced_by", "worked_at").
    var relationshipType: String?

    /// A confidence score for the relationship (0.0 - 1.0).
    var confidence: Double?

    /// Provenance metadata describing the nature of the relationship.
    var provenance: Provenance?

    /// Evidence supporting this relationship.
    var evidence: [Evidence] = []

    static func == (lhs: Edge, rhs: Edge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
