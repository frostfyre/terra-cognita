import Foundation

/// User-facing graph layout algorithms. The currently-applied one is
/// surfaced via the Layout menu in the toolbar (Phase 1) and
/// persisted per-vault. Phase 0 wires the type; Phase 1 implements
/// the radial / hierarchical / grid algorithms and the menu UI;
/// Phase 3 fills in `cluster` once community detection lands.
enum LayoutAlgorithm: String, Codable, CaseIterable, Identifiable, Hashable {
    case forceDirected
    case circular
    case radial
    case hierarchical
    case grid
    case cluster

    var id: String { rawValue }

    /// Display label for the Layout menu.
    var displayName: String {
        switch self {
        case .forceDirected: return "Force-directed"
        case .circular:      return "Circular"
        case .radial:        return "Radial"
        case .hierarchical:  return "Hierarchical"
        case .grid:          return "Grid"
        case .cluster:       return "Cluster"
        }
    }

    /// SF Symbol for the Layout menu (per DESIGN.md).
    var systemImage: String {
        switch self {
        case .forceDirected: return "point.3.connected.trianglepath.dotted"
        case .circular:      return "circle.dotted"
        case .radial:        return "target"
        case .hierarchical:  return "arrow.triangle.branch"
        case .grid:          return "square.grid.3x3"
        case .cluster:       return "circle.grid.hex"
        }
    }

    /// Whether Phase 1 ships an implementation for this algorithm.
    /// `cluster` is gated on Phase 3's community detection landing.
    var isImplemented: Bool {
        switch self {
        case .forceDirected, .circular: return true   // existing
        case .radial, .hierarchical, .grid: return false  // Phase 1
        case .cluster: return false                       // Phase 3
        }
    }
}
