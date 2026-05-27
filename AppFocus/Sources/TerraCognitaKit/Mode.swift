import Foundation

/// What kind of graph a vault is. Drives default node types, the
/// available launch templates, the default lens, and downstream UI
/// affordances. Persisted as a string in vault metadata so older
/// vaults that predate the mode tag are read as `.continuity` —
/// that's the only case shipped today; `worldbuild` and
/// `projectArchaeology` land in Phase 2.
///
/// See DESIGN.md for the per-mode user journey and template list.
enum Mode: String, Codable, CaseIterable, Identifiable, Hashable {
    case continuity
    // Reserved for Phase 2.
    // case worldbuild
    // case projectArchaeology

    var id: String { rawValue }

    /// Human-readable label for menus and the toolbar mode pill.
    var displayName: String {
        switch self {
        case .continuity: return "Continuity"
        }
    }

    /// SF Symbol the toolbar mode pill renders.
    var systemImage: String {
        switch self {
        case .continuity: return "clock.arrow.circlepath"
        }
    }
}
