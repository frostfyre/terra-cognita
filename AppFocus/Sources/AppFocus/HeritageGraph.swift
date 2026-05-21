import Foundation

/// A container for the entire heritage graph.
/// Holds nodes and edges and provides basic manipulation APIs.
final class HeritageGraph {
    /// A dictionary of all nodes in the graph, keyed by their ID.
    private(set) var nodes: [String: Node] = [:]

    /// An array of all edges in the graph.
    private(set) var edges: [Edge] = []

    /// Adds a node to the graph. Replaces any existing node with the same ID.
    func addNode(_ node: Node) {
        nodes[node.id] = node
    }

    /// Adds an edge to the graph, only if both endpoints exist.
    func addEdge(_ edge: Edge) {
        guard nodes[edge.sourceID] != nil, nodes[edge.targetID] != nil else {
            return
        }
        edges.append(edge)
    }

    /// Retrieves a node by its ID.
    func getNode(byID id: String) -> Node? { nodes[id] }
}
