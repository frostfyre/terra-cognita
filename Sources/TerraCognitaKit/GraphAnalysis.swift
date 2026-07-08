import Foundation

/// Graph-topology analysis utilities. Backs Phase 3's Systems lens
/// and Cluster layout.
///
/// All entry points are synchronous and pure — caller is expected to
/// dispatch heavy work to a background `Task` if needed. On atlas
/// scale (a few hundred nodes / few thousand edges) the algorithms
/// run in single-digit milliseconds.
enum GraphAnalysis {

    // MARK: - Community detection (Label Propagation)

    /// Partition the graph into communities using the Label
    /// Propagation Algorithm — each node iteratively adopts the most
    /// common label among its neighbors until stable. Linear in
    /// edges per iteration, typically converges in <20 iterations on
    /// graphs we ship at.
    ///
    /// Returns a map from node id → compact community index (`0..<k`).
    /// Disconnected components naturally fall into their own
    /// communities.
    static func communityPartition(of graph: Graph,
                                   iterations: Int = 20) -> [String: Int] {
        let nodeIDs = Array(graph.nodes.keys)
        guard !nodeIDs.isEmpty else { return [:] }

        let adjacency = undirectedAdjacency(of: graph)

        // Initialize: each node is its own community.
        var labels: [String: Int] = [:]
        labels.reserveCapacity(nodeIDs.count)
        for (i, id) in nodeIDs.enumerated() { labels[id] = i }

        // Iterate. Random visit order improves convergence quality.
        for _ in 0..<iterations {
            var changed = false
            for id in nodeIDs.shuffled() {
                let neighbors = adjacency[id] ?? []
                guard !neighbors.isEmpty else { continue }
                var counts: [Int: Int] = [:]
                for n in neighbors {
                    guard let l = labels[n] else { continue }
                    counts[l, default: 0] += 1
                }
                guard let winner = counts.max(by: { $0.value < $1.value })?.key
                else { continue }
                if labels[id] != winner {
                    labels[id] = winner
                    changed = true
                }
            }
            if !changed { break }
        }

        // Compact labels to 0..<k so callers can use them as palette
        // indices without sparse gaps.
        var remap: [Int: Int] = [:]
        var nextIndex = 0
        var out: [String: Int] = [:]
        out.reserveCapacity(nodeIDs.count)
        for id in nodeIDs {
            let raw = labels[id] ?? 0
            if let m = remap[raw] {
                out[id] = m
            } else {
                remap[raw] = nextIndex
                out[id] = nextIndex
                nextIndex += 1
            }
        }
        return out
    }

    // MARK: - Bridge nodes

    /// Bridge nodes — node ids whose neighbors span ≥2 communities.
    /// These are the "seamwalkers" of the graph: the connectors that
    /// hold otherwise-separate regions together.
    static func bridgeNodes(of graph: Graph,
                            partition: [String: Int]) -> Set<String> {
        let adjacency = undirectedAdjacency(of: graph)
        var bridges: Set<String> = []
        for id in graph.nodes.keys {
            let myCluster = partition[id]
            var others: Set<Int> = []
            for n in adjacency[id] ?? [] {
                if let c = partition[n], c != myCluster {
                    others.insert(c)
                    if others.count >= 1 { break }
                }
            }
            if !others.isEmpty { bridges.insert(id) }
        }
        return bridges
    }

    // MARK: - Connected components

    /// Connected-component list. Each component is the set of node
    /// ids reachable from any starting member by following edges in
    /// either direction. Used by the Systems lens to surface orphan
    /// islands.
    static func connectedComponents(of graph: Graph) -> [Set<String>] {
        let adjacency = undirectedAdjacency(of: graph)
        var visited: Set<String> = []
        var components: [Set<String>] = []
        for start in graph.nodes.keys where !visited.contains(start) {
            var stack = [start]
            var component: Set<String> = []
            while let id = stack.popLast() {
                if !visited.insert(id).inserted { continue }
                component.insert(id)
                for n in adjacency[id] ?? [] where !visited.contains(n) {
                    stack.append(n)
                }
            }
            components.append(component)
        }
        return components
    }

    // MARK: - Helpers

    private static func undirectedAdjacency(of graph: Graph) -> [String: [String]] {
        var adj: [String: [String]] = [:]
        for edge in graph.edges {
            adj[edge.sourceID, default: []].append(edge.targetID)
            adj[edge.targetID, default: []].append(edge.sourceID)
        }
        return adj
    }
}
