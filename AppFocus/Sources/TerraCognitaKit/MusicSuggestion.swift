import Foundation

/// State machine for atlas-suggested music. Decides whether the
/// gentle music-note badge appears on the toolbar speaker icon, and
/// remembers per-atlas accept / decline so we don't re-pester.
///
/// Per the audio design memo, all gates must hold:
///
/// 1. Chime audio is on for this atlas (no music upsell when the
///    user has muted everything).
/// 2. The atlas carries an author-curated `suggestedMusic` field.
/// 3. User hasn't declined for this atlas.
/// 4. User hasn't already accepted (and is therefore presumed to be
///    listening — no need to suggest what's already playing).
/// 5. Atlas has reached the theme-density floor (≥ 20 nodes — a
///    blank atlas hasn't earned a soundtrack).
///
/// State is stored in UserDefaults keyed by a stable atlas identifier
/// (the atlas's display name + node-count hash) so accept / decline
/// survives across sessions. Bundled demos (no writable URL) still
/// keyed deterministically.
@MainActor
enum MusicSuggestion {
    /// Minimum node count before the atlas has "grown into something"
    /// worth scoring. Below this, no suggestion appears regardless of
    /// author curation — we don't want a blank vault to spawn a
    /// soundtrack prompt on first open.
    static let densityFloor: Int = 20

    /// Decide whether the badge should be visible for the current
    /// atlas. Pure read against the gates above — call from view
    /// state so SwiftUI re-evaluates on relevant changes.
    static func shouldOffer(for store: GraphStore) -> Bool {
        guard store.config.audio.chimeEnabled,
              let _ = store.config.audio.suggestedMusic,
              !hasDeclined(for: store),
              !hasAccepted(for: store),
              store.graph.nodes.count >= densityFloor else {
            return false
        }
        return true
    }

    // MARK: - Per-atlas accept / decline persistence

    /// Mark the user as having declined the suggestion for the
    /// current atlas. Suggestion never re-appears for this atlas
    /// unless the user explicitly invokes it (future menu item).
    static func recordDecline(for store: GraphStore) {
        UserDefaults.standard.set(true, forKey: declinedKey(for: store))
    }

    /// Mark the user as having accepted — playback is presumed
    /// active, so the suggestion shouldn't compete with itself.
    static func recordAccept(for store: GraphStore) {
        UserDefaults.standard.set(true, forKey: acceptedKey(for: store))
    }

    /// Wipe the per-atlas state — used by a "Reset suggestion" menu
    /// item the user can invoke if they want to see the prompt again.
    /// Not wired to UI yet; here for future use.
    static func resetState(for store: GraphStore) {
        UserDefaults.standard.removeObject(forKey: declinedKey(for: store))
        UserDefaults.standard.removeObject(forKey: acceptedKey(for: store))
    }

    private static func hasDeclined(for store: GraphStore) -> Bool {
        UserDefaults.standard.bool(forKey: declinedKey(for: store))
    }

    private static func hasAccepted(for store: GraphStore) -> Bool {
        UserDefaults.standard.bool(forKey: acceptedKey(for: store))
    }

    /// Stable per-atlas key. Uses the writable atlas URL when present
    /// (so user-picked vaults are distinguishable across machines via
    /// the same iCloud-synced UserDefaults), falls back to a hash of
    /// the suggestion ID for bundled demos.
    private static func atlasKey(for store: GraphStore) -> String {
        if let url = store.writableAtlasURL {
            return url.standardizedFileURL.path
        }
        if let s = store.config.audio.suggestedMusic {
            return "demo::\(s.id)"
        }
        return "demo::unknown"
    }

    private static func declinedKey(for store: GraphStore) -> String {
        "music.suggestion.declined::\(atlasKey(for: store))"
    }

    private static func acceptedKey(for store: GraphStore) -> String {
        "music.suggestion.accepted::\(atlasKey(for: store))"
    }
}
