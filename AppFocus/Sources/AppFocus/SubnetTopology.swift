import Foundation

/// Derived structural decomposition of a heritage graph into subnets.
///
/// A node is a **hub** if its degree exceeds `hubDegreeThreshold`. Every
/// non-hub node is assigned to *its strongest hub neighbour* — the
/// adjacent hub with the highest overall degree (ties broken
/// alphabetically). Non-hub nodes with no hub neighbour remain at top
/// level as "wilderness" entries.
///
/// At the top level the canvas shows hubs + wilderness. Members are
/// hidden until the user enters a subnet, at which point only that
/// subnet's hub + members are visible. This is the Houdini "node has
/// an interior" pattern translated to the heritage graph.
struct SubnetTopology: Equatable {
    /// All hub node ids (subnet roots).
    var hubs: Set<String> = []
    /// Non-hub node id → its containing hub id.
    var membership: [String: String] = [:]
    /// Hub id → list of member node ids, for quick "inside-subnet" lookup.
    var members: [String: [String]] = [:]

    /// True if `id` is shown at the top level (no subnet entered).
    func isTopLevel(_ id: String) -> Bool {
        membership[id] == nil
    }

    /// True if `id` is inside the named subnet (or *is* its root).
    func isInside(_ id: String, subnet rootID: String) -> Bool {
        id == rootID || membership[id] == rootID
    }

    /// How many members the subnet has, used to scale rim-port count.
    func memberCount(of rootID: String) -> Int {
        members[rootID]?.count ?? 0
    }
}

extension SubnetTopology {
    /// Compute the topology from a `Graph`. Cheap enough to run at load
    /// time — O(V + E) for adjacency, O(V·D) for hub neighbour scan.
    static func compute(from graph: Graph,
                        hubDegreeThreshold: Int = 6) -> SubnetTopology {
        // 1. Adjacency (undirected) + degree.
        var adj: [String: [String]] = [:]
        adj.reserveCapacity(graph.nodes.count)
        for edge in graph.edges {
            adj[edge.sourceID, default: []].append(edge.targetID)
            adj[edge.targetID, default: []].append(edge.sourceID)
        }
        let degree: [String: Int] = adj.mapValues(\.count)

        // 2. Hubs.
        var hubs: Set<String> = []
        for (id, d) in degree where d >= hubDegreeThreshold {
            hubs.insert(id)
        }

        // 3. Assign each non-hub node to its strongest hub neighbour.
        var membership: [String: String] = [:]
        for (id, neighbours) in adj where !hubs.contains(id) {
            var bestHub: String?
            var bestDegree = -1
            for neighbour in neighbours where hubs.contains(neighbour) {
                let d = degree[neighbour] ?? 0
                if d > bestDegree {
                    bestDegree = d
                    bestHub = neighbour
                } else if d == bestDegree, let current = bestHub, neighbour < current {
                    bestHub = neighbour
                }
            }
            if let hub = bestHub {
                membership[id] = hub
            }
        }

        // 4. Inverted index: hub → members.
        var members: [String: [String]] = [:]
        for (memberID, hub) in membership {
            members[hub, default: []].append(memberID)
        }

        return SubnetTopology(hubs: hubs, membership: membership, members: members)
    }
}
