import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Render-side helpers consumed by the Metal "Pro" renderer. Kept on
/// `GraphStore` (rather than in the Metal view) so both renderers
/// would share the same node-radius / node-color math if we ever
/// want the Canvas path to read from here too.
extension GraphStore {

    /// World-space position for a node id, if a layout pass has
    /// committed one. Returns `nil` while the graph is loading or
    /// before the first settle.
    func layoutPosition(for nodeID: String) -> CGPoint? {
        nodePositions[nodeID]
    }

    /// Node radius in world units. Degree-coupled (hub nodes are
    /// bigger) with the same `min/max/sqrt(degree)` curve the Canvas
    /// path uses. Zoom coupling is handled by the camera, not by
    /// per-node radius, so this is purely a function of the graph.
    func nodeRadius(for nodeID: String) -> CGFloat {
        let degree = graph.adjacencyDegree(of: nodeID)
        let base = renderMinNodeRadius
            + renderDegreeRadiusFactor * CGFloat(sqrt(Double(degree)))
        return min(base, renderMaxNodeRadius)
    }

    /// RGBA components (0–1) of a node's display color. Resolves
    /// the `TypeSpec` from `config`, then platform-converts the
    /// SwiftUI Color via UIKit/AppKit. Falls back to a soft warm
    /// white when the type is unrecognized.
    func nodeColorComponents(for node: Node) -> (Float, Float, Float, Float) {
        let color = config.typeSpec(named: node.type)?.color ?? .white
        return Self.rgba(of: color)
    }

    static func rgba(of color: Color) -> (Float, Float, Float, Float) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Float(r), Float(g), Float(b), Float(a))
        #elseif canImport(AppKit)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Float(r), Float(g), Float(b), Float(a))
        #else
        return (0.85, 0.85, 0.85, 1.0)
        #endif
    }
}

// MARK: - Numbers shared between renderers
//
// Mirrors the constants in `GraphCanvasView` so the Metal renderer
// produces visually similar disc sizes. Kept here (not on
// `GraphStore`) because they're rendering tuning, not graph state.
private let renderMinNodeRadius: CGFloat = 10
private let renderDegreeRadiusFactor: CGFloat = 2.4
private let renderMaxNodeRadius: CGFloat = 28

// MARK: - Graph adjacency degree

extension Graph {
    /// Undirected degree of a node — count of edges where this id is
    /// either endpoint. O(edges) per call; cheap enough at our scale
    /// and avoids paying the upfront cost of an adjacency dictionary
    /// for renderers that only sample a handful of degrees.
    func adjacencyDegree(of nodeID: String) -> Int {
        var n = 0
        for edge in edges {
            if edge.sourceID == nodeID || edge.targetID == nodeID { n += 1 }
        }
        return n
    }
}
