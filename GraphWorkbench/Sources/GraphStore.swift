import Foundation
import Combine

final class GraphStore: ObservableObject {
    @Published private(set) var graph = HeritageGraph()

    // Indices for fast queries
    @Published private(set) var adjacency: [String: Set<String>] = [:]
    @Published private(set) var inbound: [String: Set<String>] = [:]
    @Published private(set) var outbound: [String: Set<String>] = [:]

    func load(from gexfURL: URL) throws {
        let parser = GEXFParser(fileURL: gexfURL)
        try parser.parse()
        graph = parser.graph
        rebuildIndices()
    }

    func rebuildIndices() {
        var adj: [String: Set<String>] = [:]
        var inb: [String: Set<String>] = [:]
        var outb: [String: Set<String>] = [:]

        for edge in graph.edges {
            outb[edge.sourceID, default: []].insert(edge.targetID)
            inb[edge.targetID, default: []].insert(edge.sourceID)
            adj[edge.sourceID, default: []].insert(edge.targetID)
            adj[edge.targetID, default: []].insert(edge.sourceID)
        }

        adjacency = adj
        inbound = inb
        outbound = outb
    }

    func add(_ node: Node) {
        graph.addNode(node)
    }

    func add(_ edge: Edge) {
        graph.addEdge(edge)
        rebuildIndices()
    }
}
