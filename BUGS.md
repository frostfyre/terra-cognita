# Known Issues

## iOS — merge-duplicate-cluster doesn't persist across launches
**Status:** fix shipped 2026-05-31 (`GraphStore.mergeNode` + `rewriteWikilinks`); awaiting device confirmation
**Reported:** 2026-05-31

User reports that on iOS, every cold launch surfaces the same
duplicate cluster banner. Tapping Review → Merge clears the banner
within the current session, but on relaunch the duplicate is back.

Suspected cause: `GraphStore.mergeNode` performs three file ops
(write merged winner body, snapshot loser, delete loser .md) inside
a `startAccessingSecurityScopedResource` bracket, but uses `try?`
for the snapshot + delete — so iOS sandbox / Files-app provider
rejections fail silently. The in-memory graph is updated either
way, which is why the cluster appears merged in-session. Next
launch, the loser .md is still on disk → loader re-detects the
cluster.

Fix shipped:
1. Two new static helpers `GraphStore.coordinatedWrite` and
   `coordinatedDelete` wrap the write/delete in
   `NSFileCoordinator.coordinate(writingItemAt:options:)` on iOS
   (`.forReplacing` for writes, `.forDeleting` for the loser-file
   removal). macOS path is unchanged. Matches the existing
   `coordinatedLoad` read-side coordinator pattern.
2. The loser-file delete in step 3 is now `do try ... catch` — if
   the delete fails, the merge returns a real error message
   ("Couldn't delete loser file at …") BEFORE the in-memory
   cleanup runs, so on-disk and in-memory state stay in sync and
   the user can retry.
3. `rewriteWikilinks` step 2 uses `coordinatedWrite` for the .bak
   snapshot + the actual file rewrite. Per-file failures log to
   console but don't abort the whole sweep — partial rewrites
   are recoverable from the per-file .bak.

Next test: tap Review → merge → cold relaunch. Banner should now
stay clear.

## Layout transitions teleported on large graphs
**Status:** fixed in `GraphCanvasView.beginLayoutTransition` + `effectivePosition`, confirmed on device 2026-05-31
**Reported:** 2026-05-31

Switching layout algorithms (or toggling no-overlap) snapped nodes
instantly to their new positions on the heritage atlas, even though
the call sites were wrapped in `withAnimation(.spring(...))`. Root
cause: SwiftUI `withAnimation` only animates view-tree properties;
values read inside a `Canvas` draw closure aren't part of that
tree, so the position dictionary updated instantaneously regardless
of the wrapping. Symptom was hidden on small graphs where the
displacement per node was tiny.

Fix: explicit per-frame interpolation. `LayoutTransition` snapshots
the old `layout`, stores the new target, and `effectivePosition`
lerps each node from `from` to `to` based on wallclock delta over
~0.8 s (easeOutQuart — no overshoot, so the field "lands" cleanly
on big atlases). The 20 Hz TimelineView re-reads positions per
tick, so the Canvas samples the interpolation naturally. The
transition state auto-clears once duration elapses.

Pinning was removed in the same pass — drag now writes directly
into `layout` (still persisted across launches).

## Fit view still feels off
**Status:** fixed in `frameHighlightedSubnet` + `frameAllVisible` on 2026-05-29
**Reported:** 2026-05-28

Two bugs caught: (1) the offset calc divided by 1.0 implicitly,
so when the selected node sat on a non-foreground depth layer
(parallax factor `pf = 0.55 + 0.45 * depth` < 1) the camera
centered on a phantom point off to one side. Fix: divide
`-centerWorld * scale` by the selected node's actual `pf`. (2)
The bbox-to-scale math used a world-space pad (`+80`) that
didn't translate cleanly across zoom levels, so labels + halos
spilled past the edge once the candidate scale shrank. Fix:
drop the world pad, add a screen-space `labelMargin: 80` on
both axes (chrome margin still separate) so the rendered extent
of label pills + node radii has room regardless of scale.

If the camera still misses on certain selections, the most
likely remaining cause is mixed-depth neighborhoods —
`frameAllVisible` assumes foreground pf=1 for the offset, which
slightly biases when the bbox spans backgrounded nodes only.
Worth revisiting if it bites.

## iOS: heritage folder loads as 0 nodes / 0 edges
**Status:** instrumented, awaiting on-device repro
**Reported:** 2026-05-27

User copied the heritage atlas folder to iOS, picked it via Open
Atlas Folder → status shows 0 nodes / 0 edges. Same folder loads
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

`AtlasLoader.load()` now returns `(Graph, Diagnostics)` and
`GraphStore.load(from:)` surfaces the diag counts in the load
status when nodes.count == 0, distinguishing #1 (`walked N items
but no .md`) from #2 (`folder access was denied`) from #3
(`walked N, M .md but none parsed`). Next on-device repro should
say which.

iOS reads now also go through `NSFileCoordinator.coordinate(readingItemAt:)`
in `GraphStore.coordinatedLoad(at:config:)` — this handles cause
#2 preemptively for iCloud-Drive / Files-app folders that won't
yield to `FileManager.enumerator` from the security-scoped
bracket alone. macOS skips the coordinator wrap.

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


## Atlas browser — "Open Atlas Folder…" inert on iOS
**Status:** fix shipped, awaiting confirmation on device
**Reported:** 2026-05-26

Two earlier attempts (`202b101` deferral, `202b101` separated Bool +
mode pair) didn't land. Now using a `UIDocumentPickerViewController`
wrapped in a `UIViewControllerRepresentable` (`FolderPicker.swift`),
presented via `.sheet` on iOS only. macOS keeps SwiftUI's
`.fileImporter` since it works there. Test path: tap Atlas → "Open
Atlas Folder…" — Files document picker should mount full-screen.

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
2. `GEXFImporter.writeAtlas` now pre-seeds `usedFilenames` with any
   `.md` slugs already present at the destination, so re-imports
   into a populated folder are additive instead of overwriting.

If duplicates still appear:
- Constellation may propose two nodes with the same label in the
  same batch. Current behaviour: second is treated as existing and
  links are appended to the first (`GraphStore.applyConstellation`).
  No double-node is created, but the user gets no warning. If you
  want a warning, add a pass in `applyConstellation` before phase 1.
