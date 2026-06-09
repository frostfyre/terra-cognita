import Foundation

/// Parses an Apple Music share URL into the parts the app needs to
/// construct a `SuggestedMusic` binding. URLs from Music.app's
/// **Share → Copy Link** look like:
///
///   https://music.apple.com/us/playlist/joe-hisaishi-essentials/pl.9d00…
///   https://music.apple.com/us/album/spirited-away-soundtrack/1717021756
///   https://music.apple.com/us/song/one-summer-day/1717021757
///
/// Path components: `/REGION/TYPE/SLUG/ID`. `TYPE` is one of
/// `playlist`, `album`, `song`. `ID` is the catalog identifier
/// (playlist IDs start `pl.`; album / song are numeric strings).
///
/// Anything that isn't a music.apple.com URL pointing at one of the
/// three supported kinds returns `nil`.
enum MusicURLParser {
    struct Parsed: Equatable {
        let kind: AtlasConfig.SuggestedMusic.Kind
        let id: String
    }

    static func parse(_ input: String) -> Parsed? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host.hasSuffix("music.apple.com") else {
            return nil
        }

        // pathComponents on `/us/playlist/slug/pl.xxx` yields
        // ["/", "us", "playlist", "slug", "pl.xxx"]. We need at least
        // 5 entries.
        let components = url.pathComponents
        guard components.count >= 5 else { return nil }
        guard let kind = AtlasConfig.SuggestedMusic.Kind(rawValue: components[2].lowercased()) else {
            return nil
        }
        let rawID = components[4]
        guard !rawID.isEmpty else { return nil }
        return Parsed(kind: kind, id: rawID)
    }
}
