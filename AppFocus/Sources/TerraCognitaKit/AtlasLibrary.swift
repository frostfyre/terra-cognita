import Foundation

/// Persistent list of atlases the user has opened.
///
/// Each `Entry` is a security-scoped bookmark plus enough metadata to
/// surface a useful menu of "recent atlases" without re-resolving every
/// bookmark on launch. Stored in `UserDefaults` as a JSON-encoded array.
///
/// `AtlasBookmark` still stores the *currently-active* atlas, used at
/// app launch. `AtlasLibrary` augments that with a recent-history list.
struct AtlasLibrary: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id: UUID
        var displayName: String
        var bookmark: Data
        /// Last time the user opened this atlas. Drives ordering.
        var lastOpened: Date
        /// Stats from the most recent load (best-effort; not always known).
        var nodeCount: Int?
        var edgeCount: Int?
    }

    var entries: [Entry] = []
    /// Hard cap so the menu doesn't grow without bound.
    static let maxEntries = 12

    // MARK: - Mutation helpers

    /// Insert or update an entry for `url`. Moves it to the top of the
    /// list (LRU semantics). Stores a fresh security-scoped bookmark.
    mutating func touch(_ url: URL,
                       displayName: String? = nil,
                       nodeCount: Int? = nil,
                       edgeCount: Int? = nil) {
        let name = displayName ?? url.lastPathComponent
        let bookmark: Data = (try? Self.makeBookmark(url)) ?? Data()
        // Drop any existing entry pointing at the same URL — match by
        // displayName + path so we tolerate stale bookmark bytes.
        entries.removeAll { $0.displayName == name }
        let entry = Entry(
            id: UUID(),
            displayName: name,
            bookmark: bookmark,
            lastOpened: .now,
            nodeCount: nodeCount,
            edgeCount: edgeCount
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
    }

    /// Resolve an entry's bookmark to a usable URL. Refreshes the stored
    /// bookmark if the system reports it stale.
    mutating func resolve(entryID: UUID) -> URL? {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        do {
            var stale = false
            let url = try Self.resolveBookmark(entries[idx].bookmark, isStale: &stale)
            if stale, let fresh = try? Self.makeBookmark(url) {
                entries[idx].bookmark = fresh
            }
            entries[idx].lastOpened = .now
            // Move-to-front
            let entry = entries.remove(at: idx)
            entries.insert(entry, at: 0)
            return url
        } catch {
            return nil
        }
    }

    mutating func remove(entryID: UUID) {
        entries.removeAll { $0.id == entryID }
    }

    // MARK: - Persistence

    private static let key = "TerraCognita.vaultLibrary"

    static func load() -> AtlasLibrary {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return AtlasLibrary()
        }
        return (try? JSONDecoder().decode(AtlasLibrary.self, from: data)) ?? AtlasLibrary()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: - Bookmark plumbing

    private static func makeBookmark(_ url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(options: [.withSecurityScope],
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil)
        #else
        return try url.bookmarkData(options: [],
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil)
        #endif
    }

    private static func resolveBookmark(_ data: Data, isStale: inout Bool) throws -> URL {
        #if os(macOS)
        return try URL(resolvingBookmarkData: data,
                       options: [.withSecurityScope],
                       relativeTo: nil,
                       bookmarkDataIsStale: &isStale)
        #else
        return try URL(resolvingBookmarkData: data,
                       options: [],
                       relativeTo: nil,
                       bookmarkDataIsStale: &isStale)
        #endif
    }
}
