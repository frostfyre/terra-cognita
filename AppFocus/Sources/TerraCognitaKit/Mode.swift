import Foundation

/// What kind of graph a vault is. Set at vault creation (via the
/// template picker) and persisted in `.terracognita/config.yaml`
/// alongside types and eras. Drives the toolbar mode pill, the
/// default node-type vocabulary, and the launch-template selector.
///
/// See `DESIGN.md` for the per-mode user journey + template list.
enum Mode: String, Codable, CaseIterable, Identifiable, Hashable {
    /// Lived continuity over time — people, careers, stories, lineages.
    case continuity
    /// Fictional or conceptual terrain — invented worlds, conceptual
    /// landscapes, transmedia lore.
    case worldbuild
    /// Discovered topology — file / code / asset structures.
    case projectArchaeology

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .continuity:         return "Continuity"
        case .worldbuild:         return "Worldbuild"
        case .projectArchaeology: return "Project Archaeology"
        }
    }

    /// SF Symbol the toolbar mode pill renders.
    var systemImage: String {
        switch self {
        case .continuity:         return "clock.arrow.circlepath"
        case .worldbuild:         return "globe.americas"
        case .projectArchaeology: return "folder.fill.badge.gearshape"
        }
    }

    /// One-line summary for the template picker.
    var summary: String {
        switch self {
        case .continuity:
            return "Lives, careers, stories, lineages — graphs over time."
        case .worldbuild:
            return "Invented worlds and conceptual terrain — authored, not discovered."
        case .projectArchaeology:
            return "Discovered topology — code, assets, files, dependencies."
        }
    }
}
