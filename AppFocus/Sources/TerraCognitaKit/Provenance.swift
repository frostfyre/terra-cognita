import Foundation

/// Provenance categories for edges, aligned with DESIGN.md.
enum Provenance: String, Codable, CaseIterable, Hashable {
    case directInfluence
    case verifiedLineage
    case institutionalConnection
    case inferredAffinity
    case recommendation
    case adjacency
    case speculation
}

/// Evidence attached to a relationship to support provenance.
struct Evidence: Codable, Hashable {
    var description: String
    var links: [URL] = []
    /// IDs of local notes or external references that support the relationship.
    var noteIDs: [String] = []
}
