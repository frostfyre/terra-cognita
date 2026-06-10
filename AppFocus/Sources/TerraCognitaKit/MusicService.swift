import Foundation
import MusicKit

/// Apple Music integration for atlas-suggested soundtracks. Wraps
/// MusicKit's authorization + playback in a single `@MainActor`
/// service so the UI doesn't have to know about MusicKit's
/// authorization state machine.
///
/// **Player choice is platform-specific.** On iOS / iPadOS we use
/// `SystemMusicPlayer` — playback flows through the system Music
/// app, visible in Control Center, lock-screen, AirPlay, etc. so the
/// atlas suggestion becomes "start this music wherever I am."
/// `SystemMusicPlayer` is unavailable on macOS, so on macOS we fall
/// back to `ApplicationMusicPlayer` (app-bound playback that ends
/// when Terra Cognita exits). The compromise is unavoidable — the
/// Music-app handoff doesn't exist on macOS in the framework.
///
/// Authorization is requested **lazily** — never on app launch, only
/// when the user accepts a suggestion. Honors the discover-on-opt-in
/// principle: no Apple Music permission prompt unless the user has
/// already decided they want music.
@MainActor
final class MusicService {
    static let shared = MusicService()

    private init() {}

    /// Current authorization state. Lazy — never call `request()`
    /// implicitly; the caller decides when to ask the user.
    var authorizationStatus: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    /// Ask the user for MusicKit permission. Safe to call when
    /// already authorized — returns the current status without
    /// re-prompting. Returns `.authorized` on success.
    func requestAuthorization() async -> MusicAuthorization.Status {
        let current = MusicAuthorization.currentStatus
        if current == .authorized || current == .denied {
            return current
        }
        return await MusicAuthorization.request()
    }

    /// Start playback of the given atlas-suggested music through the
    /// system Music app. Requests authorization if needed; returns
    /// `.success` on playback start, or a specific failure case the
    /// caller can surface to the user.
    func play(_ suggestion: AtlasConfig.SuggestedMusic) async -> PlayResult {
        let status = await requestAuthorization()
        guard status == .authorized else {
            return status == .denied ? .denied : .unavailable
        }

        do {
            switch suggestion.kind {
            case .playlist:
                let id = MusicItemID(suggestion.id)
                let request = MusicCatalogResourceRequest<Playlist>(
                    matching: \.id, equalTo: id)
                let response = try await request.response()
                guard let playlist = response.items.first else {
                    return .notFound
                }
                try await play(playlist)
            case .album:
                let id = MusicItemID(suggestion.id)
                let request = MusicCatalogResourceRequest<Album>(
                    matching: \.id, equalTo: id)
                let response = try await request.response()
                guard let album = response.items.first else {
                    return .notFound
                }
                try await play(album)
            case .song:
                let id = MusicItemID(suggestion.id)
                let request = MusicCatalogResourceRequest<Song>(
                    matching: \.id, equalTo: id)
                let response = try await request.response()
                guard let song = response.items.first else {
                    return .notFound
                }
                try await play(song)
            }
            return .success
        } catch {
            return .failure(error)
        }
    }

    /// Catalog search — single-string query against the Apple Music
    /// catalog returning songs, albums, and playlists that match.
    /// Backs the in-app music picker so the user can find what they
    /// want without leaving the app. Caller is expected to debounce
    /// keystrokes; this method makes one network round-trip per call.
    func search(query: String, limit: Int = 25) async -> SearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let status = await requestAuthorization()
        guard status == .authorized else {
            return status == .denied ? .denied : .unavailable
        }

        do {
            var request = MusicCatalogSearchRequest(
                term: trimmed,
                types: [Song.self, Album.self, Playlist.self])
            request.limit = limit
            let response = try await request.response()
            let songs = response.songs.map { song in
                SearchItem(id: song.id.rawValue,
                           kind: .song,
                           title: song.title,
                           subtitle: song.artistName,
                           artworkURL: song.artwork?.url(width: 80, height: 80))
            }
            let albums = response.albums.map { album in
                SearchItem(id: album.id.rawValue,
                           kind: .album,
                           title: album.title,
                           subtitle: album.artistName,
                           artworkURL: album.artwork?.url(width: 80, height: 80))
            }
            let playlists = response.playlists.map { playlist in
                SearchItem(id: playlist.id.rawValue,
                           kind: .playlist,
                           title: playlist.name,
                           subtitle: playlist.curatorName,
                           artworkURL: playlist.artwork?.url(width: 80, height: 80))
            }
            return .results(songs: songs, albums: albums, playlists: playlists)
        } catch {
            return .failure(error)
        }
    }

    /// Catalog lookup — given a kind + ID, fetch the human-readable
    /// name + attribution so the manual music-picker UI can show the
    /// user what they're about to bind to. Same authorization path
    /// as playback. Returns `.notFound` if the ID doesn't resolve
    /// (typo or out-of-date catalog).
    func lookup(kind: AtlasConfig.SuggestedMusic.Kind, id: String) async -> LookupResult {
        let status = await requestAuthorization()
        guard status == .authorized else {
            return status == .denied ? .denied : .unavailable
        }

        do {
            switch kind {
            case .playlist:
                let request = MusicCatalogResourceRequest<Playlist>(
                    matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                guard let item = response.items.first else { return .notFound }
                return .found(displayName: item.name,
                              attribution: item.curatorName)
            case .album:
                let request = MusicCatalogResourceRequest<Album>(
                    matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                guard let item = response.items.first else { return .notFound }
                return .found(displayName: item.title,
                              attribution: item.artistName)
            case .song:
                let request = MusicCatalogResourceRequest<Song>(
                    matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                guard let item = response.items.first else { return .notFound }
                return .found(displayName: item.title,
                              attribution: item.artistName)
            }
        } catch {
            return .failure(error)
        }
    }

    /// Stop the active music player. Used when the user toggles audio
    /// off and we want to honor the silence preference completely.
    func stop() {
        #if os(iOS) || os(visionOS)
        SystemMusicPlayer.shared.stop()
        #else
        ApplicationMusicPlayer.shared.stop()
        #endif
    }

    private func play<Item: PlayableMusicItem>(_ item: Item) async throws {
        #if os(iOS) || os(visionOS)
        let player = SystemMusicPlayer.shared
        player.queue = [item]
        try await player.play()
        #else
        let player = ApplicationMusicPlayer.shared
        player.queue = [item]
        try await player.play()
        #endif
    }

    /// Result of a `play(...)` call. Mapped to user-facing copy by
    /// the caller — keep the cases stable so the UI doesn't have to
    /// pattern-match on error messages.
    enum PlayResult {
        case success
        /// User explicitly denied MusicKit access. Caller should
        /// surface a "you can re-enable in Settings" hint.
        case denied
        /// Authorization is restricted (parental controls, etc.) or
        /// the device can't grant access. Suggestion stays available
        /// but the suggestion UI should explain why playback failed.
        case unavailable
        /// The catalog ID didn't resolve to a real Apple Music item.
        /// Likely an out-of-date author suggestion.
        case notFound
        /// Underlying MusicKit / network error.
        case failure(Error)
    }

    /// Result of a `lookup(...)` call — used by the manual music
    /// picker to verify a pasted URL resolves before saving it as
    /// the atlas's binding. Failure paths mirror `PlayResult` so
    /// callers can share error-handling helpers.
    enum LookupResult {
        case found(displayName: String, attribution: String?)
        case notFound
        case denied
        case unavailable
        case failure(Error)
    }

    /// One result row from a catalog search — kind-tagged so the
    /// picker can render an appropriate badge and save with the
    /// right `SuggestedMusic.Kind`.
    struct SearchItem: Identifiable, Hashable {
        let id: String
        let kind: AtlasConfig.SuggestedMusic.Kind
        let title: String
        let subtitle: String?
        let artworkURL: URL?
    }

    /// Result of a `search(...)` call. Empty query returns `.empty`
    /// without a network round-trip. Authorization failures mirror
    /// the other results so the picker can share handling code.
    enum SearchResult {
        case empty
        case results(songs: [SearchItem], albums: [SearchItem], playlists: [SearchItem])
        case denied
        case unavailable
        case failure(Error)
    }
}
