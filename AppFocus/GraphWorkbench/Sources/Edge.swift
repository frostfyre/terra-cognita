import Foundation

/// Represents a directed edge between two nodes in the heritage graph.
struct Edge: Identifiable, Equatable {
    /// A unique identifier for the edge.
    let id: String
    
    /// The identifier of the source node.
    let sourceID: String
    
    /// The identifier of the target node.
    let targetID: String
    
    /// The type of relationship (e.g., "influenced_by", "worked_at").
    /// This can be expanded based on your design's provenance principles.
    var relationshipType: String?
    
    /// A confidence score for the relationship.
    var confidence: Double?

    static func == (lhs: Edge, rhs: Edge) -> Bool {
        lhs.id == rhs.id
    }
}
