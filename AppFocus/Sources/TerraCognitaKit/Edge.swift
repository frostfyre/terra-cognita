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

    /// True if this edge was produced by an extractor (`#tag` →
    /// `tag:` node, `![[file]]` → `embed:` node) rather than
    /// declared by the user as a wikilink. Synthetic edges have no
    /// literal line in any source `.md` to rewrite, so the edge
    /// editor refuses to mutate them.
    ///
    /// Targets carrying `attributes["synthetic"] == "true"` are also
    /// synthetic, but that requires looking up the node — callers
    /// that already have the target in hand can combine both checks
    /// via the `Graph` helper below.
    var isSynthetic: Bool {
        relationshipType == "tagged" || relationshipType == "embeds"
    }

    static func == (lhs: Edge, rhs: Edge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Node {
    /// True for placeholder / tag / embed nodes materialized by the
    /// loader's extractors. These don't have user-authored backing
    /// files; editing affordances usually skip them.
    var isSynthetic: Bool {
        attributes["synthetic"] == "true"
    }
}
