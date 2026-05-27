import Foundation
import CoreGraphics

/// Pure deterministic layout algorithms. Each returns a world-space
/// positions dictionary keyed by node id. Force-directed lives in
/// `ForceDirectedLayout.swift` (separate file, separate engine);
/// these are the cheaper, deterministic options that compose with the
/// Layout selector in Phase 1.
enum LayoutEngine {

    // MARK: - Grid

    /// √N × √N grid, deterministic order. Good for auditing —
    /// every node visible, equal weight, no implicit hierarchy.
    static func grid(nodeIDs: [String]) -> [String: CGPoint] {
        let ids = nodeIDs.sorted()
        let n = ids.count
        guard n > 0 else { return [:] }
        let cols = max(1, Int(ceil(sqrt(Double(n)))))
        let spacing: CGFloat = 110
        let originX = -CGFloat(cols - 1) * spacing / 2
        var out: [String: CGPoint] = [:]
        out.reserveCapacity(n)
        for (i, id) in ids.enumerated() {
            let col = i % cols
            let row = i / cols
            let rows = (n + cols - 1) / cols
            let originY = -CGFloat(rows - 1) * spacing / 2
            out[id] = CGPoint(
                x: originX + CGFloat(col) * spacing,
                y: originY + CGFloat(row) * spacing
            )
        }
        return out
    }

    // MARK: - Radial (concentric)

    /// Concentric rings centered on `root`. Ring 0 is the root, ring 1
    /// its direct neighbors, ring 2 the next BFS layer, etc. Nodes the
    /// BFS can't reach (disconnected components) land on an outer
    /// ring sorted by id. If `root` is nil, picks the highest-degree
    /// node so there's always a sensible centerpiece.
    static func radial(nodeIDs: [String],
                       adjacency: [String: [String]],
                       root: String?) -> [String: CGPoint] {
        guard !nodeIDs.isEmpty else { return [:] }
        let pivot = root ?? highestDegree(of: nodeIDs, adjacency: adjacency) ?? nodeIDs[0]

        // BFS layering from the pivot.
        var depthByID: [String: Int] = [pivot: 0]
        var frontier: [String] = [pivot]
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                let d = depthByID[id, default: 0]
                for neighbor in adjacency[id] ?? [] where depthByID[neighbor] == nil {
                    depthByID[neighbor] = d + 1
                    next.append(neighbor)
                }
            }
            frontier = next
        }

        // Anything unreached → push onto a synthetic outermost ring.
        let maxKnownDepth = depthByID.values.max() ?? 0
        let orphans = nodeIDs.filter { depthByID[$0] == nil }
        for id in orphans { depthByID[id] = maxKnownDepth + 1 }

        // Group by ring.
        var ringMembers: [Int: [String]] = [:]
        for id in nodeIDs {
            let d = depthByID[id, default: 0]
            ringMembers[d, default: []].append(id)
        }

        var out: [String: CGPoint] = [:]
        out.reserveCapacity(nodeIDs.count)
        let ringSpacing: CGFloat = 160
        for (depth, members) in ringMembers {
            let sorted = members.sorted()
            if depth == 0, let first = sorted.first {
                out[first] = .zero
                continue
            }
            let radius = ringSpacing * CGFloat(depth)
            let count = sorted.count
            // Phase-offset rings slightly so neighbors don't land directly
            // on the radial axis — visually breaks up the spokes.
            let phase = Double(depth) * 0.5
            for (i, id) in sorted.enumerated() {
                let angle = 2 * .pi * Double(i) / Double(count) + phase
                out[id] = CGPoint(
                    x: radius * CGFloat(cos(angle)),
                    y: radius * CGFloat(sin(angle))
                )
            }
        }
        return out
    }

    // MARK: - Hierarchical (BFS layers)

    /// BFS layering top-to-bottom from `root` (or the highest-degree
    /// node if root is nil). Each layer becomes a row, nodes evenly
    /// spaced within the row. Disconnected nodes go in a final row
    /// at the bottom.
    static func hierarchical(nodeIDs: [String],
                             adjacency: [String: [String]],
                             root: String?) -> [String: CGPoint] {
        guard !nodeIDs.isEmpty else { return [:] }
        let pivot = root ?? highestDegree(of: nodeIDs, adjacency: adjacency) ?? nodeIDs[0]

        var depthByID: [String: Int] = [pivot: 0]
        var frontier: [String] = [pivot]
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                let d = depthByID[id, default: 0]
                for neighbor in adjacency[id] ?? [] where depthByID[neighbor] == nil {
                    depthByID[neighbor] = d + 1
                    next.append(neighbor)
                }
            }
            frontier = next
        }
        let maxKnownDepth = depthByID.values.max() ?? 0
        let orphans = nodeIDs.filter { depthByID[$0] == nil }
        for id in orphans { depthByID[id] = maxKnownDepth + 1 }

        var rowMembers: [Int: [String]] = [:]
        for id in nodeIDs {
            let d = depthByID[id, default: 0]
            rowMembers[d, default: []].append(id)
        }

        let rowSpacing: CGFloat = 140
        let colSpacing: CGFloat = 110
        var out: [String: CGPoint] = [:]
        out.reserveCapacity(nodeIDs.count)
        // Center the rows vertically around y = 0.
        let totalRows = (rowMembers.keys.max() ?? 0) + 1
        let yOrigin = -CGFloat(totalRows - 1) * rowSpacing / 2
        for (depth, members) in rowMembers {
            let sorted = members.sorted()
            let count = sorted.count
            let xOrigin = -CGFloat(count - 1) * colSpacing / 2
            let y = yOrigin + CGFloat(depth) * rowSpacing
            for (i, id) in sorted.enumerated() {
                out[id] = CGPoint(x: xOrigin + CGFloat(i) * colSpacing, y: y)
            }
        }
        return out
    }

    // MARK: - No-overlap post-pass

    /// Iteratively push colliding nodes apart until no pair sits closer
    /// than `minDistance`. Position-stable for non-overlapping nodes
    /// (idempotent when there's nothing to fix). Runs in O(n² · iters)
    /// — fine for vault scale.
    ///
    /// `pinned` ids are anchors: they never move. When a pinned node
    /// collides with a free node, the free node absorbs the full
    /// displacement.
    static func enforceNoOverlap(_ positions: [String: CGPoint],
                                 pinned: Set<String> = [],
                                 minDistance: CGFloat = 56,
                                 iterations: Int = 8) -> [String: CGPoint] {
        guard positions.count > 1 else { return positions }
        var out = positions
        let ids = Array(positions.keys)
        let minDistSq = minDistance * minDistance

        for _ in 0..<iterations {
            var moved = false
            for i in 0..<ids.count {
                let a = ids[i]
                guard var pa = out[a] else { continue }
                for j in (i + 1)..<ids.count {
                    let b = ids[j]
                    guard var pb = out[b] else { continue }
                    let dx = pb.x - pa.x
                    let dy = pb.y - pa.y
                    let distSq = dx * dx + dy * dy
                    if distSq >= minDistSq || distSq == 0 {
                        if distSq == 0 {
                            // Co-located: nudge along a deterministic axis
                            // so iteration can take over from there.
                            pb.x += 0.1
                            out[b] = pb
                        }
                        continue
                    }
                    let dist = sqrt(distSq)
                    let overlap = (minDistance - dist) / 2
                    let nx = dx / dist
                    let ny = dy / dist
                    let aPinned = pinned.contains(a)
                    let bPinned = pinned.contains(b)
                    if aPinned && bPinned {
                        continue // both anchored; nothing to do
                    } else if aPinned {
                        pb.x += nx * overlap * 2
                        pb.y += ny * overlap * 2
                        out[b] = pb
                    } else if bPinned {
                        pa.x -= nx * overlap * 2
                        pa.y -= ny * overlap * 2
                        out[a] = pa
                    } else {
                        pa.x -= nx * overlap
                        pa.y -= ny * overlap
                        pb.x += nx * overlap
                        pb.y += ny * overlap
                        out[a] = pa
                        out[b] = pb
                    }
                    moved = true
                }
            }
            if !moved { break }
        }
        return out
    }

    // MARK: - Helpers

    private static func highestDegree(of nodeIDs: [String],
                                      adjacency: [String: [String]]) -> String? {
        nodeIDs.max(by: { (adjacency[$0]?.count ?? 0) < (adjacency[$1]?.count ?? 0) })
    }
}
