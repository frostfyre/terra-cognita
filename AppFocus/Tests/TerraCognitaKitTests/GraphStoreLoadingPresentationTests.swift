import Testing
import Foundation
@testable import TerraCognitaKit

/// Lifecycle tests for the loading-presentation API on `GraphStore` —
/// the surface that drives whether the cold-start splash / glyph is
/// up, when it dismisses, and whether atlas switches re-mount it.
///
/// Two invariants this suite locks down (both shipped in 2026-06-07
/// commits and previously had zero coverage):
///   1. The splash is visible for a minimum of 3 s on cold start —
///      `finishLoadingPresentation()` honors the floor by deferring
///      its dismissal when the canvas settles early.
///   2. The splash is a cold-start-only moment — after the first
///      dismissal, `startLoadingPresentation()` becomes a no-op so
///      atlas switches / mid-session reloads don't re-mount it.
@MainActor
@Suite("GraphStore loading presentation")
struct GraphStoreLoadingPresentationTests {

    @Test("init seeds a non-nil loadingCaption (splash mounts on first frame)")
    func captionPresentAtConstruction() {
        let store = GraphStore()
        #expect(store.loadingCaption != nil,
                "construction must set a caption so the LoadingScreen is the first thing visible — no white-flash gap")
    }

    @Test("startLoadingPresentation is idempotent before cold-start completes")
    func startIdempotencyDuringColdStart() {
        let store = GraphStore()
        store.startLoadingPresentation()
        #expect(store.loadingCaption != nil)
        // Calling again must not crash and must leave the caption set.
        store.startLoadingPresentation()
        #expect(store.loadingCaption != nil)
    }

    @Test("finishLoadingPresentation honors the 3 s floor, then clears, then gates further starts")
    func coldStartFloorThenGating() async throws {
        let store = GraphStore()
        #expect(store.loadingCaption != nil)

        // Finish is called immediately — the canvas settled before the
        // floor. The dismissal must be deferred, not run immediately.
        store.finishLoadingPresentation()
        try await Task.sleep(for: .milliseconds(500))
        #expect(store.loadingCaption != nil,
                "fade should not have started 500 ms in — floor is 3 s")

        // Wait the rest of the floor plus a small buffer for the
        // deferred task to schedule and the @Published write to land.
        try await Task.sleep(for: .milliseconds(2_800))
        #expect(store.loadingCaption == nil,
                "caption should be cleared after the floor elapses")

        // Cold-start has completed — any subsequent start (atlas
        // switch) must be a no-op so the splash never re-mounts.
        store.startLoadingPresentation()
        #expect(store.loadingCaption == nil,
                "post-cold-start startLoadingPresentation must not re-mount the splash")
    }
}
