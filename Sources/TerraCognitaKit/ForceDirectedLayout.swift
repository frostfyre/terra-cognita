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
    /// Iteration count. The simulation converges visibly by ~120 on
    /// the atlas scale we ship at; the rest of the runs just refine
    /// the look. 160 strikes the balance between snappy and pretty.
    var iterations: Int = 160
    /// Ideal edge length. Bigger value = more spread.
    var idealEdgeLength: Double = 140
    /// Multiplier on the cooling temperature curve. Bigger = larger steps.
    var temperatureScale: Double = 1.6
    /// Pulls every node weakly toward (0, 0). Bigger = tighter ball.
    var gravity: Double = 0.025

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

        // Barnes-Hut kicks in above this threshold. Below it, the
        // naive O(n²) pass is faster — the quadtree's per-iteration
        // build cost dominates at small N.
        let useBarnesHut = n > 200
        let theta = 0.8  // higher = more approximation, faster

        for iter in 0..<iterations {
            for i in 0..<n { dx[i] = 0; dy[i] = 0 }

            if useBarnesHut {
                // O(n log n) repulsion via Barnes-Hut quadtree.
                // Build tree per iteration — particles have moved.
                var tree = BarnesHutTree(particleCount: n)
                tree.build(px: px, py: py)
                for i in 0..<n {
                    let (fx, fy) = tree.repulsion(
                        onParticleAt: px[i], py: py[i],
                        kSquared: kSquared, theta: theta)
                    dx[i] += fx
                    dy[i] += fy
                }
            } else {
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

// MARK: - Barnes-Hut quadtree

/// Barnes-Hut quadtree for n-body repulsion. Trades exactness for
/// O(n log n) per iteration by approximating distant clusters of
/// particles as a single point-mass at their center of mass when
/// the cluster's bounding size over the distance is below `theta`.
///
/// Layout is flat — children live in a single growable array so the
/// hot inner loop walks contiguous memory rather than chasing
/// reference-counted node pointers. This is the perf-critical
/// difference between "Barnes-Hut speeds layout up" and "Barnes-Hut
/// is slower than the naive O(n²) at our scale."
private struct BarnesHutTree {
    /// Flat node storage. Index 0 is always the root.
    private var nodes: [Node] = []
    /// Bounds derived from particle extents at build time.
    private var rootBounds: Bounds = Bounds()

    struct Node {
        /// Bounds of this node's region.
        var bounds: Bounds = Bounds()
        /// Sum of x · mass over all contained particles.
        var sumX: Double = 0
        /// Sum of y · mass over all contained particles.
        var sumY: Double = 0
        /// Number of particles in this node — also serves as mass
        /// (every particle weighs 1 in this layout).
        var count: Int = 0
        /// First-child index when this is an internal node.
        /// `-1` means leaf. Children occupy 4 consecutive slots
        /// starting at this index, in NW / NE / SW / SE order.
        var firstChild: Int = -1
        /// Particle index when this is a leaf with a single body.
        /// `-1` means no particle (empty leaf, possible during
        /// the temporary state of subdivision).
        var particle: Int = -1
    }

    struct Bounds {
        var xMin: Double = 0
        var yMin: Double = 0
        var xMax: Double = 0
        var yMax: Double = 0

        var size: Double { max(xMax - xMin, yMax - yMin) }
        var cx: Double { (xMin + xMax) * 0.5 }
        var cy: Double { (yMin + yMax) * 0.5 }
    }

    init(particleCount: Int) {
        // Rough capacity hint — a sparsely-populated tree has roughly
        // 2-4 nodes per particle. Reserve enough to avoid most realloc.
        nodes.reserveCapacity(particleCount * 4)
    }

    mutating func build(px: [Double], py: [Double]) {
        nodes.removeAll(keepingCapacity: true)
        let n = px.count
        guard n > 0 else { return }

        var xMin = px[0], xMax = px[0]
        var yMin = py[0], yMax = py[0]
        for i in 1..<n {
            if px[i] < xMin { xMin = px[i] }
            if px[i] > xMax { xMax = px[i] }
            if py[i] < yMin { yMin = py[i] }
            if py[i] > yMax { yMax = py[i] }
        }
        // Pad so particles aren't on the boundary.
        let pad = max(xMax - xMin, yMax - yMin) * 0.05 + 1.0
        rootBounds = Bounds(xMin: xMin - pad, yMin: yMin - pad,
                            xMax: xMax + pad, yMax: yMax + pad)

        var root = Node()
        root.bounds = rootBounds
        nodes.append(root)

        for i in 0..<n {
            insert(particle: i, px: px, py: py, into: 0)
        }
    }

    private mutating func insert(particle p: Int,
                                 px: [Double], py: [Double],
                                 into idx: Int) {
        // Accumulate COM along the way down.
        let x = px[p], y = py[p]
        nodes[idx].sumX += x
        nodes[idx].sumY += y
        nodes[idx].count += 1

        if nodes[idx].firstChild == -1 {
            // Leaf path.
            if nodes[idx].particle == -1 {
                // Empty leaf — just stash the particle here.
                nodes[idx].particle = p
                return
            }
            // Occupied leaf — subdivide. Move the resident
            // particle into the right child, then recurse for
            // the new one too.
            let resident = nodes[idx].particle
            nodes[idx].particle = -1
            subdivide(idx)
            placeIntoChild(particle: resident,
                           px: px, py: py, of: idx)
        }
        placeIntoChild(particle: p, px: px, py: py, of: idx)
    }

    private mutating func subdivide(_ idx: Int) {
        let parentBounds = nodes[idx].bounds
        let mx = parentBounds.cx
        let my = parentBounds.cy
        let firstChild = nodes.count
        // NW, NE, SW, SE — order chosen so child(particle) below
        // can map (x>=mx, y>=my) → 0..3 with a single bit-shift.
        let childBounds: [Bounds] = [
            Bounds(xMin: parentBounds.xMin, yMin: parentBounds.yMin,
                   xMax: mx, yMax: my),                                // NW (0)
            Bounds(xMin: mx, yMin: parentBounds.yMin,
                   xMax: parentBounds.xMax, yMax: my),                 // NE (1)
            Bounds(xMin: parentBounds.xMin, yMin: my,
                   xMax: mx, yMax: parentBounds.yMax),                 // SW (2)
            Bounds(xMin: mx, yMin: my,
                   xMax: parentBounds.xMax, yMax: parentBounds.yMax),  // SE (3)
        ]
        for b in childBounds {
            var child = Node()
            child.bounds = b
            nodes.append(child)
        }
        nodes[idx].firstChild = firstChild
    }

    private mutating func placeIntoChild(particle p: Int,
                                         px: [Double], py: [Double],
                                         of idx: Int) {
        let parentBounds = nodes[idx].bounds
        let east = px[p] >= parentBounds.cx ? 1 : 0
        let south = py[p] >= parentBounds.cy ? 2 : 0
        let child = nodes[idx].firstChild + east + south
        insert(particle: p, px: px, py: py, into: child)
    }

    /// Repulsion accumulator for a single source particle, walking
    /// the tree iteratively (no recursion → much cheaper at scale).
    func repulsion(onParticleAt x: Double, py y: Double,
                   kSquared: Double, theta: Double) -> (Double, Double) {
        guard !nodes.isEmpty else { return (0, 0) }
        var fx = 0.0
        var fy = 0.0
        var stack: [Int] = [0]
        stack.reserveCapacity(64)
        let thetaSq = theta * theta

        while let idx = stack.popLast() {
            let node = nodes[idx]
            if node.count == 0 { continue }
            let mass = Double(node.count)
            let cx = node.sumX / mass
            let cy = node.sumY / mass
            var ddx = x - cx
            var ddy = y - cy
            let distSq = max(ddx * ddx + ddy * ddy, 0.0001)
            let s = node.bounds.size

            // Use this cell as a point-mass if it's a leaf or the
            // size/distance criterion is satisfied (s/d < theta).
            let isLeaf = node.firstChild == -1
            if isLeaf || (s * s) < thetaSq * distSq {
                // Skip self-interaction — leaf containing the same
                // particle as the query (distSq is tiny).
                if isLeaf && node.particle >= 0 && distSq < 0.0001 {
                    continue
                }
                let dist = sqrt(distSq)
                let force = kSquared * mass / dist
                ddx /= dist
                ddy /= dist
                fx += ddx * force
                fy += ddy * force
            } else {
                // Recurse into the four children.
                let c = node.firstChild
                stack.append(c)
                stack.append(c + 1)
                stack.append(c + 2)
                stack.append(c + 3)
            }
        }
        return (fx, fy)
    }
}
