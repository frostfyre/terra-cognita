#!/usr/bin/env swift

// Stress-test the two heaviest non-UI operations as a function of graph
// size: ForceDirectedLayout and SubnetTopology. Builds a synthetic
// graph with realistic structure (a small number of high-degree hubs +
// many leaves connecting to one or two hubs) and times each stage.
//
//   swift -O scripts/stress_test.swift   # release-mode (recommended)
//   swift    scripts/stress_test.swift   # debug-mode (much slower)
//
// Note: this is a standalone script — it duplicates the ForceDirectedLayout
// and SubnetTopology algorithms in-line because Swift script files can't
// import non-system modules. Numbers are representative of release perf
// when run with `-O`.

import Foundation
import CoreGraphics

// ----- Simplified ForceDirectedLayout (mirrors TerraCognitaKit) ------

struct StressLayout {
    var iterations: Int = 260
    var idealEdgeLength: Double = 140
    var temperatureScale: Double = 1.6
    var gravity: Double = 0.025

    func compute(nodeIDs: [String], edges: [(String, String)]) -> [String: CGPoint] {
        let n = nodeIDs.count
        guard n > 1 else { return [:] }
        var idIndex: [String: Int] = [:]
        for (i, id) in nodeIDs.enumerated() { idIndex[id] = i }
        var px = [Double](repeating: 0, count: n)
        var py = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let angle = 2 * .pi * Double(i) / Double(n)
            let r = idealEdgeLength * 4
            px[i] = cos(angle) * r
            py[i] = sin(angle) * r
        }
        var edgeIdx: [(Int, Int)] = []
        for (s, t) in edges {
            if let i = idIndex[s], let j = idIndex[t], i != j { edgeIdx.append((i, j)) }
        }
        let k = idealEdgeLength
        let kSquared = k * k
        var dx = [Double](repeating: 0, count: n)
        var dy = [Double](repeating: 0, count: n)
        for iter in 0..<iterations {
            for i in 0..<n { dx[i] = 0; dy[i] = 0 }
            // Repulsion
            for i in 0..<n {
                let xi = px[i], yi = py[i]
                for j in (i+1)..<n {
                    var ddx = xi - px[j]
                    var ddy = yi - py[j]
                    let dist = max(sqrt(ddx*ddx + ddy*ddy), 0.01)
                    let f = kSquared / dist
                    ddx /= dist; ddy /= dist
                    dx[i] += ddx * f; dy[i] += ddy * f
                    dx[j] -= ddx * f; dy[j] -= ddy * f
                }
            }
            // Attraction
            for (i, j) in edgeIdx {
                var ddx = px[i] - px[j]
                var ddy = py[i] - py[j]
                let dist = max(sqrt(ddx*ddx + ddy*ddy), 0.01)
                let f = (dist*dist) / k
                ddx /= dist; ddy /= dist
                dx[i] -= ddx * f; dy[i] -= ddy * f
                dx[j] += ddx * f; dy[j] += ddy * f
            }
            // Gravity
            for i in 0..<n {
                dx[i] -= px[i] * gravity
                dy[i] -= py[i] * gravity
            }
            let t = max(k * temperatureScale * (1.0 - Double(iter) / Double(iterations)), 1.0)
            for i in 0..<n {
                let mag = max(sqrt(dx[i]*dx[i] + dy[i]*dy[i]), 0.01)
                px[i] += (dx[i] / mag) * min(mag, t)
                py[i] += (dy[i] / mag) * min(mag, t)
            }
        }
        var out: [String: CGPoint] = [:]
        for i in 0..<n { out[nodeIDs[i]] = CGPoint(x: px[i], y: py[i]) }
        return out
    }
}

// ----- Simplified SubnetTopology compute (mirrors TerraCognitaKit) ----

struct StressTopology {
    var hubs: Set<String> = []
    var membership: [String: String] = [:]
    var bridges: Set<String> = []

    static func compute(nodeIDs: [String], edges: [(String, String)], threshold: Int = 6) -> StressTopology {
        var adj: [String: [String]] = [:]
        for (s, t) in edges {
            adj[s, default: []].append(t)
            adj[t, default: []].append(s)
        }
        var hubs: Set<String> = []
        for (id, n) in adj where n.count >= threshold { hubs.insert(id) }
        var membership: [String: String] = [:]
        for (id, neighbours) in adj where !hubs.contains(id) {
            var best: String?; var bestDeg = -1
            for n in neighbours where hubs.contains(n) {
                let d = adj[n]?.count ?? 0
                if d > bestDeg { bestDeg = d; best = n }
            }
            if let h = best { membership[id] = h }
        }
        var bridges: Set<String> = []
        for (id, neighbours) in adj {
            var homes: Set<String> = []
            for n in neighbours {
                if hubs.contains(n) { homes.insert(n) }
                else if let h = membership[n] { homes.insert(h) }
            }
            if homes.count >= 2 { bridges.insert(id) }
        }
        var topo = StressTopology()
        topo.hubs = hubs; topo.membership = membership; topo.bridges = bridges
        return topo
    }
}

// ----- Synthetic graph builder ------------------------------------

/// Builds a graph that roughly mirrors a heritage vault: ~5% hubs with
/// dozens of connections each, the rest leaves with 1-3 edges each.
func syntheticGraph(nodeCount: Int) -> (ids: [String], edges: [(String, String)]) {
    var rng = SystemRandomNumberGenerator()
    let ids = (0..<nodeCount).map { "n\($0)" }
    let hubCount = max(1, nodeCount / 20)
    let hubs = Array(ids.prefix(hubCount))
    var edges: [(String, String)] = []
    // Inter-hub edges (sparse mesh)
    for i in 0..<hubs.count {
        for j in (i+1)..<hubs.count {
            if Double.random(in: 0..<1, using: &rng) < 0.25 {
                edges.append((hubs[i], hubs[j]))
            }
        }
    }
    // Leaves attach to 1-3 hubs each
    for leaf in ids.dropFirst(hubCount) {
        let attachments = Int.random(in: 1...3, using: &rng)
        var seen: Set<String> = []
        for _ in 0..<attachments {
            let h = hubs.randomElement(using: &rng)!
            if !seen.contains(h) {
                edges.append((leaf, h))
                seen.insert(h)
            }
        }
    }
    return (ids, edges)
}

// ----- Bench runner -----------------------------------------------

func bench(_ label: String, _ block: () -> Void) -> Double {
    let start = Date()
    block()
    return Date().timeIntervalSince(start)
}

func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
}

print(pad("nodes", 7) + pad("edges", 10) + pad("layout(s)", 12)
      + pad("topo(s)", 10) + "rate")
print(String(repeating: "-", count: 56))

let sizes = [100, 300, 500, 1000, 2000, 3000, 5000]
for n in sizes {
    let (ids, edges) = syntheticGraph(nodeCount: n)
    let layout = StressLayout()
    let layoutTime = bench("layout") {
        _ = layout.compute(nodeIDs: ids, edges: edges)
    }
    let topoTime = bench("topo") {
        _ = StressTopology.compute(nodeIDs: ids, edges: edges)
    }
    let total = layoutTime + topoTime
    let rate = total > 0 ? "\(Int(Double(n) / total)) n/s" : "—"
    print(pad("\(n)", 7)
          + pad("\(edges.count)", 10)
          + pad(String(format: "%.3f", layoutTime), 12)
          + pad(String(format: "%.3f", topoTime), 10)
          + rate)
}
