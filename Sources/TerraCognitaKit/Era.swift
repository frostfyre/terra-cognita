import Foundation

/// Chronological ordering for the atlas's era taxonomy.
///
/// `era:` is the most consistently-populated dateish field on heritage
/// notes (`pre-conscious`, `blizzard-era`, `current`, etc.). This enum
/// pins those tags to an ordinal scale so the canvas can place nodes on
/// a perceptual depth axis: oldest era = deepest / further back, most
/// recent era = closest / on top.
enum Era: Int, CaseIterable {
    case preConscious           = 0
    case selfChoosingChildhood  = 1
    case preBlizzard            = 2
    case earlyCareer            = 3
    case blizzardEra            = 4
    case bridge                 = 5
    case postFormation          = 6
    case postBlizzard           = 7
    case current                = 8

    static func parse(_ raw: String) -> Era? {
        let key = raw.lowercased()
            .trimmingCharacters(in: .whitespaces)
        switch key {
        case "pre-conscious":            return .preConscious
        case "self-choosing-childhood":  return .selfChoosingChildhood
        case "pre-blizzard":             return .preBlizzard
        case "early-career":             return .earlyCareer
        case "blizzard-era":             return .blizzardEra
        case "bridge":                   return .bridge
        case "post-formation":           return .postFormation
        case "post-blizzard":            return .postBlizzard
        case "current":                  return .current
        default:                         return nil
        }
    }

    /// Normalised depth in [0, 1] — 0 is deepest, 1 is foreground.
    var depth: Double {
        let maxOrdinal = Double(Era.allCases.count - 1)
        return Double(rawValue) / maxOrdinal
    }

    /// The canonical front-matter tag string for this era.
    var tagValue: String {
        switch self {
        case .preConscious:           return "pre-conscious"
        case .selfChoosingChildhood:  return "self-choosing-childhood"
        case .preBlizzard:            return "pre-blizzard"
        case .earlyCareer:            return "early-career"
        case .blizzardEra:            return "blizzard-era"
        case .bridge:                 return "bridge"
        case .postFormation:          return "post-formation"
        case .postBlizzard:           return "post-blizzard"
        case .current:                return "current"
        }
    }

    /// Every era tag value plus `career-spanning`, in chronological
    /// order. Used as the choice list in the composer and the
    /// inspector's era picker.
    static var allTagValues: [String] {
        allCases.map(\.tagValue) + ["career-spanning"]
    }
}

extension Node {
    /// A perceptual depth in `[0, 1]`. Oldest era → 0 (back), most
    /// recent → 1 (front). Returns ~0.55 for nodes without a
    /// recognised era so they sit slightly forward of the deep past
    /// but behind the explicitly-present. Uses the built-in heritage
    /// era enum — the canvas calls `depth(in: config)` instead so
    /// custom atlases get their own taxonomy.
    var depth: Double {
        depth(in: nil)
    }

    /// Config-aware depth. When a `AtlasConfig` is supplied, era
    /// resolution uses *its* taxonomy and weights. Without a config,
    /// falls back to the built-in heritage `Era` enum.
    func depth(in config: AtlasConfig?) -> Double {
        let raw = attributes["era"] ?? attributes["peak-era"] ?? ""
        guard !raw.isEmpty else { return 0.55 }
        // Era values are comma-joined lists like "blizzard-era, ongoing".
        // Take the LATEST recognised era so a "career-spanning, ongoing"
        // node reads as present-day rather than ancient.
        let pieces = raw
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if let config {
            let weights = pieces.compactMap { config.eraSpec(named: $0)?.weight }
            guard let latest = weights.max() else { return 0.55 }
            let maxW = config.maxEraWeight
            return maxW > 0 ? latest / maxW : 0.55
        }

        let eras = pieces.compactMap(Era.parse)
        guard let latest = eras.map(\.rawValue).max() else { return 0.55 }
        let normalised = Double(latest) / Double(Era.allCases.count - 1)
        return normalised
    }
}
