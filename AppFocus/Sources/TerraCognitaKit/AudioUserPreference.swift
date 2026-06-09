import Foundation

/// Process-wide audio preferences, stored in UserDefaults so they
/// persist across atlas loads — even for non-writable bundled atlases
/// (the Miyazaki demo) where the per-atlas `audio:` block can't be
/// saved to disk.
///
/// The relationship to `AtlasConfig.Audio.chimeEnabled` is:
///   - `AtlasConfig.audio.chimeEnabled` is the *current atlas's*
///     effective setting at runtime (drives `ChimeSonifier` gates).
///   - `AudioUserPreference.chimeOptIn` is the *user's global choice*
///     captured by the first-launch intro and the toolbar control.
///     Applied as a default whenever an atlas loads without an
///     explicit on-disk preference.
enum AudioUserPreference {
    private static let introSeenKey   = "audio.introSeen"
    private static let chimeOptInKey  = "audio.chimeOptIn"

    /// Whether the first-launch audio intro sheet has been shown.
    /// Once true, the sheet never auto-presents again — the user is
    /// presumed to have made an explicit choice.
    static var introSeen: Bool {
        get { UserDefaults.standard.bool(forKey: introSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: introSeenKey) }
    }

    /// User's global chime preference. Default `false` (no audio
    /// until the user opts in), flipped by the intro sheet or the
    /// toolbar speaker control.
    static var chimeOptIn: Bool {
        get { UserDefaults.standard.bool(forKey: chimeOptInKey) }
        set { UserDefaults.standard.set(newValue, forKey: chimeOptInKey) }
    }
}
