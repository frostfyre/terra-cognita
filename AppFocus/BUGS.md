# Known Issues

## iOS: heritage folder loads as 0 nodes / 0 edges
**Status:** instrumented, awaiting on-device repro
**Reported:** 2026-05-27

User copied the heritage vault folder to iOS, picked it via Open
Vault Folder → status shows 0 nodes / 0 edges. Same folder loads
correctly on macOS so the source is intact. Most likely causes,
in decreasing order of likelihood:

1. **Wrong-folder pick** — the heritage tree on disk is nested
   (`Data/heritage-vault/heritage-vault/concepts/...`). Picking
   the outer `heritage-vault` wrapper yields a folder with one
   child directory and zero `.md` files. The Files-app picker
   surfaces both levels with the same name; easy to grab the
   wrong one.
2. **iOS sandboxing** — `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`
   should grant recursive read access via the security-scoped
   bracket, but iCloud-Drive folders sometimes need an
   `NSFileCoordinator.coordinate(readingItemAt:options:byAccessor:)`
   wrap before `FileManager.enumerator` will yield anything.
3. **Encoding issue** — the loader's encoding fallback chain runs
   per file, so this is a long-shot; would surface as "found
   N .md but parsed 0 nodes."

`VaultLoader.load()` now returns `(Graph, Diagnostics)` and
`GraphStore.load(from:)` surfaces the diag counts in the load
status when nodes.count == 0, distinguishing #1 (`walked N items
but no .md`) from #2 (`folder access was denied`) from #3
(`walked N, M .md but none parsed`). Next on-device repro should
say which.

## Capture / AI ops crashed on graphs with duplicate-labelled nodes
**Status:** fixed, awaiting confirmation
**Reported:** 2026-05-27

Three iOS crash reports pulled from device, all the same root cause:
`Dictionary(uniqueKeysWithValues:)` traps on duplicate keys. The
crash sites were the label → display-name lookup tables in
`NodeIntelligence.extractConstellation` (Capture), `enrich`
(Capture's web pass), and `suggestConnections` (AI links on a
selected node). Any graph containing two nodes whose
lowercased labels collided (typical after a GEXF import that
includes e.g. both "Star Trek (franchise)" and "Star Trek (1979
film)" → `star-trek.md` + `star-trek-2.md`, both with the heading
"Star Trek") would crash the moment the user invoked Capture or AI
suggestions.

Switched all three to `Dictionary(_:uniquingKeysWith:)` keeping the
first encountered display label on collision.


## Vault browser — "Open Vault Folder…" inert on iOS
**Status:** fix shipped, awaiting confirmation on device
**Reported:** 2026-05-26

Two earlier attempts (`202b101` deferral, `202b101` separated Bool +
mode pair) didn't land. Now using a `UIDocumentPickerViewController`
wrapped in a `UIViewControllerRepresentable` (`FolderPicker.swift`),
presented via `.sheet` on iOS only. macOS keeps SwiftUI's
`.fileImporter` since it works there. Test path: tap Vault → "Open
Vault Folder…" — Files document picker should mount full-screen.

## Can't pinch-zoom out far enough on iOS
**Status:** fix shipped, awaiting confirmation on device
**Reported:** 2026-05-26

Pinch (and scroll/persisted-scale) clamps centralized as
`minScale`/`maxScale` on `GraphCanvasView`. Lower bound dropped from
0.25 to 0.10 — about 4× more zoom-out headroom. `frameAllVisible`
shares the same floor so direct manipulation can always reach what
the auto-frame produces.

## Duplicates banner kept firing
**Status:** likely fixed, awaiting confirmation
**Reported:** 2026-05-26

Two changes:
1. `GraphStore.duplicateClusters()` no longer buckets by
   label-normalized form. Legitimate distinct same-label nodes
   (e.g. GEXF imports with both "Star Trek (franchise)" and "Star
   Trek (1979 film)" → `star-trek.md` and `star-trek-2.md`) were
   being clustered together by the shared `# Star Trek` heading.
   We now cluster by id-normalized form only, which still catches
   the canonical case ("Usenet job posting" / "usenet-job-posting").
2. `GEXFImporter.writeVault` now pre-seeds `usedFilenames` with any
   `.md` slugs already present at the destination, so re-imports
   into a populated folder are additive instead of overwriting.

If duplicates still appear:
- Constellation may propose two nodes with the same label in the
  same batch. Current behaviour: second is treated as existing and
  links are appended to the first (`GraphStore.applyConstellation`).
  No double-node is created, but the user gets no warning. If you
  want a warning, add a pass in `applyConstellation` before phase 1.
