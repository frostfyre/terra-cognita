# Terra Cognita

A native Apple-platform workbench (macOS, iPad, iPhone) that treats a
heritage graph — a markdown vault of people, events, institutions,
works, and concepts — as the primary work surface. Navigable,
queryable, AI-augmented, and meant to feel like *moving through a
place* rather than reading a document.

See [`Design/DESIGN.md`](Design/DESIGN.md) for the original design /
vision document.

---

## Status

**Working preview.** Builds and runs as three targets sharing one Swift
package (`TerraCognitaKit`):

- **TerraCognita-macOS** — macOS 14+ `.app`
- **TerraCognita-iOS** — iPhone + iPad universal, iOS 17+
- **TerraCognita** — SwiftPM exec for the fastest dev loop on macOS (`swift run TerraCognita`)

All three are debug + release green. Foundation Models AI features
require macOS 26 / iOS 26.

### What's shipped

**Canvas & rendering**
- SwiftUI `Canvas` renderer (~300 nodes / ~1000 edges idle-smooth at 20 Hz)
- Force-directed layout (Fruchterman-Reingold variant, tuned toward
  Force Atlas 2), computed off the main actor and crossfaded in over a
  circular seed
- Era-driven **depth axis** with parallax-on-pan: older eras drift in
  the background, current era sits forward
- **Ambient drift** + **idle puff** so the field feels alive even when
  the user isn't interacting
- **Hover ring** (iPad pointer + Mac mouse) on the targeted node
- Persistent layout: pinned positions + scale + offset survive relaunch
- Performance: smooth to ~1,500 nodes (see `scripts/stress_test.swift`)

**Vault I/O**
- Loads any Obsidian-style markdown vault — YAML front-matter as node
  attributes, `[[wikilinks]]` + Dataview `key:: [[target]]` as typed edges
- Bundled **Miyazaki demo vault** ships with both app targets
- Open / Create New Vault via folder picker; drag-folder-onto-canvas
  works on macOS and iPadOS Stage Manager
- Security-scoped bookmarks for cross-launch persistence
- Recent-vaults library (LRU-12)
- Read-only refusal on the bundled demo (creation routes through
  Create-New-Vault)

**Navigation & focus**
- Lens picker: All / People / Concepts / Institutions / Events / Works /
  **Seamwalkers** (nodes whose neighbors span ≥ 2 subnets — a
  computed "bridge" lens)
- **Subnet decomposition + dive-in**: hubs (degree ≥ 6) collapse their
  members at top level; the "Dive into [Hub]" pill enters them
- **Forward / back navigation** (⌘[ / ⌘]) over selection + subnet state
- **Find** (⌘F): fuzzy search with prefix / word-prefix / initials match
- Inspector show / hide independent of selection (⌘I)
- **Privacy toggle** (eye): nodes with `private: true` in front-matter
  drop out of canvas + search + edges when hidden — useful for
  screenshots

**Node ingestion / authoring**
- **+ New Node** (⌘N) — composer sheet with type / label / era /
  body / private toggle; pre-fills wikilink to current selection
- **Long-press empty canvas → "Create node here"** — spatial drop-in
  creation with the spawn point captured in world coordinates,
  auto-pinned, auto-framed
- Compose-time dedup — normalized-slug collisions block the write and
  offer "Open existing / Rename"
- **Inspector ⋯ menu** — Delete this node (with `.bak` snapshot) and
  Merge into… (vault-wide `[[loser]] → [[winner]]` rewrite, body
  append, edge re-targeting)
- **Duplicate-cluster banner** on vault load with one-click merge review

**AI integration (FoundationModels, macOS 26 / iOS 26)**
- Free-form chat per node ("Ask about this node…")
- One-shot **Summarize** and **Explain connection to neighbor**
- **8 structured operations** with accept/reject proposal chips:
  - Find links in current graph
  - Suggest connections (semantic affinity)
  - Suggest era
  - Find and link public works (creates new `work` nodes)
  - Extract key concepts (creates new `concept` nodes)
  - Rewrite — concise / expanded / formal
- **Capture flow** (⌘⇧N): text + on-device voice
  (`SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`) → AI
  extracts a constellation of nodes + edges, fetches Wikipedia
  enrichment in parallel for each, asks for additional links to the
  existing graph from the enriched body. Review pane lets you toggle
  individual nodes before commit.
- Structured generation throughout (`@Generable` + `respond(to:generating:)`)

**Safety rails**
- `.bak` snapshot written on first edit per file per session (covers
  link appends, body rewrites, merges, deletes)
- Compose-time dedup prevents silent `" 2"` filename collisions
- AI link operations constrain candidates to labels that actually
  exist in the graph (no inventing nodes that don't exist)
- Read-only vault refusal — the `+` and **Capture** buttons stay
  disabled until a writable vault is open
- All speech recognition strictly on-device

**Cross-platform parity**
- Same affordances across all three platforms; adaptations only where
  the platform demands them
- Sheet vs side-panel inspector based on size class
- Pinch zoom + single-finger pan (touch) and scroll-wheel +
  middle-mouse drag (macOS)
- **Radial menu** on node long-press (Open / Dive / AI links / Center
  / Delete / Cancel) — works identically on macOS, iPad, iPhone
- Haptics on iOS (selection, subnet enter/exit, proposal accept)
- App icon (Terra Cognita orrery) rendered by `scripts/render_icon.swift`

### What's still missing / rough

- **Layout** is O(n²) — comfortable to ~1,500 nodes; ~5,000 takes ~11 s.
  Barnes-Hut would be the unblock if/when needed.
- **No live vault watch** — external edits to .md files don't show
  until next vault load.
- **No edge editing UI** — the `Provenance` model exists (7 categories)
  but isn't surfaced.
- **No 3D mode** — DESIGN.md's time-as-depth idea is hinted at via
  the parallax axis but not realized as a separate mode.
- **Capture review is modal** — a *spatial preview* (proposed nodes
  appear translucent on the canvas before commit) would feel even
  more like dive-in.
- **No graph-wide AI** — operations are all per-node; "Ask Terra
  Cognita" across the whole graph would be the next step.

---

## Build & Run

```bash
cd AppFocus

# Fastest dev loop — minimal macOS binary via SwiftPM
swift run TerraCognita

# Full macOS .app bundle
xcodebuild -project TerraCognita.xcodeproj \
           -scheme "TerraCognita-macOS" \
           -destination 'platform=macOS' build

# Universal iOS app (iPhone + iPad)
xcodebuild -project TerraCognita.xcodeproj \
           -scheme "TerraCognita-iOS" \
           -destination 'generic/platform=iOS Simulator' build
xcrun simctl install booted <path-to>/TerraCognita-iOS.app
xcrun simctl launch  booted com.frostfyre.terracognita.ios
```

`TerraCognita.xcodeproj` is generated by `scripts/generate_xcodeproj.rb`
(requires the `xcodeproj` Ruby gem). Regenerate after build-setting
changes; otherwise edit sources directly.

**Requirements:** macOS 14+ to build the Mac target, iOS 17+ to run on
device, Swift 6 toolchain, Xcode 17+. The AI / Capture features
require macOS 26 / iOS 26 (Foundation Models).

---

## Interaction

### Top bar
| Action               | Affordance                       |
|----------------------|----------------------------------|
| Back / Forward       | Chevrons · ⌘[ / ⌘]               |
| Lens picker          | Dropdown                         |
| Vault menu           | Folder icon → Open / Create New / Recent |
| New Node             | + · ⌘N                           |
| Capture (text/voice) | Bubble · ⌘⇧N                     |
| Find                 | Magnifier · ⌘F                   |
| Show/hide private    | Eye toggle                       |
| Show/hide info panel | Sidebar · ⌘I                     |

### Canvas
| Action                          | Pointer            | Touch                  |
|---------------------------------|--------------------|------------------------|
| Pan                             | Middle-mouse drag  | Single-finger drag     |
| Zoom                            | Scroll wheel       | Pinch                  |
| Select node                     | Left click         | Tap                    |
| Hover ring                      | Hover              | —                      |
| Create node here                | (long-press)       | Long-press empty area  |
| Radial action menu              | (long-press)       | Long-press on node     |
| Right-click menu                | Right click        | (long-press)           |
| Drag node                       | Click-and-drag     | Touch-and-drag         |
| Exit subnet                     | Esc                | Surface badge / Esc    |

### Inspector
- Selection auto-opens the inspector the first time; thereafter
  visibility is sticky.
- ⋯ menu → Delete this node / Merge into…
- AI section: 8 preset operations + proposal chips with ✓/✗
- Free-form chat at the bottom

---

## Project Structure

```
AppFocus/
├── Package.swift                — SwiftPM manifest (TerraCognitaKit library + TerraCognita exec)
├── TerraCognita.xcodeproj       — Generated; iOS + macOS app targets
├── Apps/
│   ├── TerraCognita-macOS/      — @main shell + Assets.xcassets
│   └── TerraCognita-iOS/        — @main shell + Assets.xcassets
├── Sources/
│   ├── TerraCognitaKit/         — Library target (the whole product)
│   │   ├── GraphView.swift              — Top-level view; top bar; all sheets
│   │   ├── GraphCanvasView.swift        — Canvas renderer; gestures; layout pipeline
│   │   ├── GraphStore.swift             — @MainActor graph state; vault I/O; ingestion
│   │   ├── NodeInspectorView.swift      — Inspector with AI ops + proposal chips
│   │   ├── NodeIntelligence.swift       — Foundation Models orchestration
│   │   ├── NodeComposer.swift           — New-node sheet
│   │   ├── CaptureSheet.swift           — Voice/text capture + constellation review
│   │   ├── Constellation.swift          — Capture proposal model
│   │   ├── NodeProposal.swift           — Per-op AI proposal model
│   │   ├── NavigationHistory.swift      — Back/forward stack
│   │   ├── RadialMenu.swift             — Long-press action wheel
│   │   ├── ForceDirectedLayout.swift    — Background FA2-ish solver
│   │   ├── LayoutPersistence.swift      — Per-vault layout snapshots
│   │   ├── Era.swift                    — Era taxonomy + depth derivation
│   │   ├── VaultLoader.swift            — Markdown vault → Graph
│   │   ├── VaultWriter.swift            — New-note creation + slug
│   │   ├── VaultEditor.swift            — In-place note edits + .bak safety
│   │   ├── VaultBookmark.swift          — Active-vault security-scoped bookmark
│   │   ├── VaultLibrary.swift           — Recent-vaults LRU
│   │   ├── VaultDropHandler.swift       — Folder drag-drop onto canvas
│   │   ├── WebEnrichment.swift          — Wikipedia REST summary client
│   │   ├── SpeechRecognizer.swift       — On-device SFSpeechRecognizer wrapper
│   │   ├── NodeSearchView.swift         — ⌘F popover
│   │   ├── MarkdownView.swift           — WKWebView markdown renderer (fallback)
│   │   ├── MarkdownBodyView.swift       — Native SwiftUI markdown for inspector
│   │   ├── Haptics.swift                — Cross-platform haptic shim
│   │   ├── Node.swift / Edge.swift / Provenance.swift — Domain types
│   │   ├── Node+File.swift              — Bundle URL lookups
│   │   ├── WebView+FileURL.swift        — Cross-platform open-in-default-app
│   │   └── Resources/miyazaki-vault/    — Bundled demo vault
│   └── TerraCognita/                    — Dev exec @main shell
├── Data/heritage-vault/         — Personal heritage vault (the dev dataset)
├── Design/DESIGN.md             — Original vision document
└── scripts/
    ├── generate_xcodeproj.rb    — Project generator (xcodeproj gem)
    ├── render_icon.swift        — App icon (Terra Cognita orrery) renderer
    └── stress_test.swift        — O(n²) layout benchmark
```

---

## Relative completeness

Roughly where the project sits against DESIGN.md and the working
roadmap:

| Area                                  | Completeness |
|---------------------------------------|--------------|
| Canvas rendering & feel               | **~95%** — depth, drift, parallax, dive-in pill, hover, idle puff |
| Vault I/O (load, create, recent)      | **~90%** — only missing live filesystem watch |
| Node ingestion (manual + AI)          | **~90%** — composer, long-press, dedup, Capture flow with voice + Wikipedia all in |
| AI integration (per-node ops)         | **~90%** — 8 ops + chat; missing graph-wide "Ask Terra Cognita" |
| AI integration (graph-wide / agentic) | **~10%** — Tool-protocol support and cross-vault AI yet to come |
| Lens system                           | **~70%** — six lenses live; provenance-driven and saved-view lenses still to come |
| Edge editing & provenance UI          | **~10%** — model exists, no UI |
| Navigation & focus management         | **~95%** — forward/back, inspector toggle, subnet dive, ESC exits, ⌘F find |
| Cross-platform parity                 | **~95%** — macOS / iPad / iPhone all shipping the same features |
| Performance (large graphs)            | **~60%** — O(n²) layout, comfortable to ~1,500 nodes; Barnes-Hut needed beyond ~2,000 |
| 3D / time-as-depth mode               | **~5%**  — hinted at via parallax; nothing standalone |
| Tests / CI                            | **~5%**  — test stubs exist; no real coverage yet |

Headline read: **MVP-feature-complete for personal use** on a graph of
up to a couple thousand nodes, with the spatial + AI ergonomics that
make it feel like a workbench rather than a viewer. Shipping at scale
(thousands of nodes, multi-user collaboration, edge-provenance editing,
saved lenses, agentic AI) is the next horizon.

---

## Roadmap

Approximate priority for the next push:

1. **Live vault watch** — `FileManager` change notifications so
   external edits show up immediately.
2. **Edge editing UI** — surface `Provenance` and `relationshipType`
   in the inspector; let the user re-classify existing edges.
3. **Spatial Capture preview** — proposed nodes materialize translucently
   on the canvas before commit, instead of in a modal review pane.
4. **Graph-wide AI** — "Ask Terra Cognita" — RAG-style query against
   the whole vault, with cited node sources.
5. **Saved lenses** — user-defined semantic views beyond the built-in
   six.
6. **Barnes-Hut layout** — O(n log n) repulsion to push the snappy
   ceiling past 5,000 nodes.
7. **3D / time-axis mode** — DESIGN.md's "time as depth" as a separate
   render mode (SceneKit or RealityKit).
