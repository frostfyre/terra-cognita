import Foundation

/// Persists the user's chosen atlas folder across app launches.
///
/// Uses security-scoped bookmarks (required for sandboxed macOS apps and
/// iOS), stored as `Data` in `UserDefaults`. On resolution we ask the
/// system to re-establish access via `startAccessingSecurityScopedResource()`;
/// the caller must balance that with `stopAccessingSecurityScopedResource()`
/// when finished.
enum AtlasBookmark {
    private static let key = "TerraCognita.vaultBookmark"

    /// Save a bookmark for the given folder URL. Returns true on success.
    @discardableResult
    static func save(_ url: URL) -> Bool {
        do {
            #if os(macOS)
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #else
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #endif
            UserDefaults.standard.set(data, forKey: key)
            return true
        } catch {
            print("[AtlasBookmark] save failed: \(error)")
            return false
        }
    }

    /// Resolve the saved bookmark to a URL. The returned URL is already
    /// security-scoped — the caller is responsible for calling
    /// `startAccessingSecurityScopedResource()` (and the balanced stop).
    static func load() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            var stale = false
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            #else
            let url = try URL(resolvingBookmarkData: data,
                              options: [],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            #endif
            if stale {
                // Refresh in the background so next launch resolves cleanly.
                _ = save(url)
            }
            return url
        } catch {
            print("[AtlasBookmark] resolve failed: \(error)")
            return nil
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
