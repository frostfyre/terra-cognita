import Foundation

/// Cartographer-voice loading captions. Cycled while an atlas
/// load is in flight so the user sees progress on a large walk
/// (the heritage atlas can take several seconds on iOS through the
/// `NSFileCoordinator` + per-file encoding-probe pass).
///
/// Voice: terra incognita, cartography, heritage — not "Loading…"
/// "Reticulating splines"-style with a Terra Cognita accent.
enum LoadingCaptions {

    /// Drawn at random for each new caption tick so a long load
    /// doesn't read the same prefix twice in a row.
    static let all: [String] = [
        "Charting unknown territory…",
        "Surveying the seams…",
        "Sketching the meridians…",
        "Triangulating influences…",
        "Translating the marginalia…",
        "Folding the eras…",
        "Aligning the constellations…",
        "Mapping the bridges…",
        "Inking the cartouche…",
        "Bound for the antipodes…",
        "Calibrating the compass…",
        "Penciling in placeholders…",
        "Annealing the layout…",
        "Untangling the wikilinks…",
        "Counting the bridge-walkers…",
        "Cross-referencing the marginalia…",
        "Naming the unnamed islands…",
        "Greasing the astrolabe…",
        "Bracing for the spinning…",
        "Consulting the older maps…",
    ]

    /// Returns a caption from `all` that is *not* equal to `previous`.
    /// Keeps the rotation from stuttering on the same line during a
    /// short load.
    static func next(after previous: String?) -> String {
        let pool = previous.map { p in all.filter { $0 != p } } ?? all
        return pool.randomElement() ?? all[0]
    }
}
