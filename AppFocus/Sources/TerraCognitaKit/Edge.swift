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

    /// Era label this edge "happened in", when meaningful. Optional;
    /// edges without an era are non-continuity-bearing in the timeline
    /// sense. Phase 3's Timeline lens reads from this.
    var era: String?

    /// Exact date this edge occurred, when known. Independent of
    /// `era` so an edge can be coarsely-dated (era only) or
    /// precisely-dated (both, or just `date`). Phase 3's Timeline
    /// lens prefers `date` over `era` when both are present.
    var date: Date?

    /// True if this edge carries any temporal anchor — `era`, `date`,
    /// or both. Used by the Timeline lens to filter to the spine.
    var isContinuityBearing: Bool { era != nil || date != nil }

    static func == (lhs: Edge, rhs: Edge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
