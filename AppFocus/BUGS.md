# Known Issues

## Vault browser — "Open Vault Folder…" still inert on iOS
**Status:** open
**Reported:** 2026-05-26

After the Menu→fileImporter deferral fix in commit `202b101`, tapping
"Open Vault Folder…" from the Vault menu on iOS still appears to do
nothing. The picker either doesn't mount or mounts and is invisible.

Likely next things to try:
- Confirm with breakpoint / log whether `showingFolderPicker` flips to
  `true` after the deferral and whether the `.fileImporter` completion
  fires at all (cancel returns `.failure` — useful signal).
- If the deferral isn't enough, the cleanest path is replacing the
  SwiftUI `.fileImporter` with a `UIViewControllerRepresentable`
  wrapper around `UIDocumentPickerViewController(forOpeningContentTypes:
  [.folder], asCopy: false)` on iOS, presented as a fullscreen sheet.
- "Create New Vault…" sits on the exact same code path and should be
  re-tested alongside.

## Can't pinch-zoom out far enough on iOS to see the whole graph
**Status:** open
**Reported:** 2026-05-26

On iOS the minimum pinch-zoom is too high — the user can't get the
camera back wide enough to see the full graph. ⌘0 / the viewfinder
button does frame everything correctly, so this is specifically a
direct-manipulation gap.

Audit:
- Find the pinch (`MagnifyGesture`) handler in `GraphCanvasView` and
  check the clamp on the resulting `scale`. The macOS minimum is
  ~0.25× (matches `frameAllVisible` floor); the iOS path may be
  clamping higher, or the gesture state may be reset between updates.
- Make sure the pinch clamp lower bound is at least as permissive as
  `frameAllVisible`'s target — otherwise the gesture can't reach what
  the auto-frame already produces.

## Duplicates keep getting generated
**Status:** open
**Reported:** 2026-05-26

After import / capture flows the duplicate-clusters banner keeps firing,
which suggests we're either creating dupes or our slug/title matching is
under-deduping at ingest time. Sources to audit:

- `GEXFImporter.writeVault` — does it re-use existing slugs across runs?
  If a vault is imported twice into the same folder we'd expect a
  collision, not a duplicate.
- `Capture` / Constellation extractor — when the AI proposes a node
  whose title matches an existing one, is the dedupe check
  case/whitespace/slug-fold sensitive enough?
- `NodeComposer` save path — same question, plus check whether
  `seedConnectionTo` ever causes a second creation of an existing node.
- Confirm the duplicate-clusters detector itself isn't too eager
  (false positives on near-but-distinct titles).
