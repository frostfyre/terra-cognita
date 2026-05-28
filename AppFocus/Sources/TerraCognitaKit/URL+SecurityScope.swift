import Foundation

/// Wrap a body in `startAccessingSecurityScopedResource` /
/// `stopAccessingSecurityScopedResource` so the bracket is
/// impossible to forget.
///
/// `start` returns `false` in two distinct cases — "no scope
/// needed, URL is already accessible" and "scope grant failed" —
/// and the platform doesn't distinguish them. We mirror the
/// existing call-site convention: only `stop` when `start`
/// returned `true`, but always run the body. Callers that need
/// to detect grant failure must do their own probe (typically
/// they'll just see an empty enumerator or a read error).
extension URL {
    /// `body` runs inside the scope and the stop is balanced via
    /// `defer`. Synchronous only — for async work that needs the
    /// bracket to outlive a `Task { ... }` boundary, keep the
    /// explicit `start` / `defer stop` pattern (capturing the
    /// `didStart` flag across the suspension point).
    func withSecurityScope<T>(_ body: () throws -> T) rethrows -> T {
        let didStart = startAccessingSecurityScopedResource()
        defer { if didStart { stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
