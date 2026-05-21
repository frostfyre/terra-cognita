import Foundation
import CoreGraphics

/// Force-directed graph layout (Fruchterman–Reingold variant, tuned to feel
/// close to Gephi's Force Atlas 2). Attractive forces along edges, repulsive
/// forces between every pair of nodes, gentle gravity toward the origin, and
/// a cooling schedule that lets the simulation settle.
///
/// Pure value-typed inputs and outputs so it's safe to run on a background
/// `Task` and hand the result back to the main actor.
struct ForceDirectedLayout: Sendable {
    var iterations: Int = 220
    /// Ideal edge length. Bigger value = more spread.
    var idealEdgeLength: Double = 80
    /// Multiplier on the cooling temperature curve. Bigger = larger steps.
    var temperatureScale: Double = 1.4
    /// Pulls every node weakly toward (0, 0). Bigger = tighter ball.
    var gravity: Double = 0.04

    func compute(nodeIDs: [String], edges: [(String, String)]) -> [String: CGPoint] {
        let n = nodeIDs.count
        guard n > 0 else { return [:] }
        if n == 1 { return [nodeIDs[0]: .zero] }

        var idIndex: [String: Int] = [:]
        idIndex.reserveCapacity(n)
        for (i, id) in nodeIDs.enumerated() { idIndex[id] = i }

        // Seed positions on a noisy ring so the simulation has something to
        // spread out from. Pure random scatter sometimes traps nodes inside
        // dense clusters they should be on the edge of.
        var px = [Double](repeating: 0, count: n)
        var py = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let angle = 2 * .pi * Double(i) / Double(n)
            let r = idealEdgeLength * 4 + Double.random(in: -10...10)
            px[i] = cos(angle) * r
            py[i] = sin(angle) * r
        }

        // Resolve edges into integer index pairs.
        var edgeIdx: [(Int, Int)] = []
        edgeIdx.reserveCapacity(edges.count)
        for (s, t) in edges {
            if let i = idIndex[s], let j = idIndex[t], i != j {
                edgeIdx.append((i, j))
            }
        }

        let k = idealEdgeLength
        let kSquared = k * k

        var dx = [Double](repeating: 0, count: n)
        var dy = [Double](repeating: 0, count: n)

        for iter in 0..<iterations {
            for i in 0..<n { dx[i] = 0; dy[i] = 0 }

            // Repulsive forces — every pair (O(n²)).
            for i in 0..<n {
                let xi = px[i], yi = py[i]
                for j in (i + 1)..<n {
                    var ddx = xi - px[j]
                    var ddy = yi - py[j]
                    let distSq = ddx * ddx + ddy * ddy
                    let dist = max(sqrt(distSq), 0.01)
                    let force = kSquared / dist
                    ddx /= dist
                    ddy /= dist
                    dx[i] += ddx * force
                    dy[i] += ddy * force
                    dx[j] -= ddx * force
                    dy[j] -= ddy * force
                }
            }

            // Attractive forces along edges.
            for (i, j) in edgeIdx {
                var ddx = px[i] - px[j]
                var ddy = py[i] - py[j]
                let dist = max(sqrt(ddx * ddx + ddy * ddy), 0.01)
                let force = (dist * dist) / k
                ddx /= dist
                ddy /= dist
                dx[i] -= ddx * force
                dy[i] -= ddy * force
                dx[j] += ddx * force
                dy[j] += ddy * force
            }

            // Gravity toward origin so disconnected components don't drift away.
            for i in 0..<n {
                dx[i] -= px[i] * gravity
                dy[i] -= py[i] * gravity
            }

            // Cooling schedule: large early steps, shrinking to ~1 by the end.
            let t = max(k * temperatureScale * (1.0 - Double(iter) / Double(iterations)), 1.0)
            for i in 0..<n {
                let mag = max(sqrt(dx[i] * dx[i] + dy[i] * dy[i]), 0.01)
                let stepX = (dx[i] / mag) * min(mag, t)
                let stepY = (dy[i] / mag) * min(mag, t)
                px[i] += stepX
                py[i] += stepY
            }
        }

        var out: [String: CGPoint] = [:]
        out.reserveCapacity(n)
        for i in 0..<n {
            out[nodeIDs[i]] = CGPoint(x: px[i], y: py[i])
        }
        return out
    }
}
