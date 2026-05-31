# Terra Cognita

A native Apple-platform workbench (macOS, iPad, iPhone) that treats a
heritage graph — a markdown atlas of people, events, institutions,
works, and concepts — as the primary work surface. Navigable,
queryable, AI-augmented, and meant to feel like *moving through a
place* rather than reading a document.

See [`DESIGN.md`](DESIGN.md) for the unified design document
(modes, lenses, layouts, vocabulary, product direction),
[`PLAN.md`](PLAN.md) for the phased implementation roadmap,
[`GENESIS.md`](GENESIS.md) for the multi-phase chat-driven
atlas-creation flow (Phase A landed; B/C/D/E next), and
[`BUGS.md`](BUGS.md) for the open / recently-fixed issue log.
[`Design/DESIGN.md`](Design/DESIGN.md) is the older original vision
document and is kept for historical context.

**Anchors:** `mvp-1.0` tag = stable feature baseline; `visual-milestone-1.0` tag = the indigo-gradient + gold-selection + curved-gradient-edges aesthetic lock-in.

> Heritage note on naming: the user-facing word is **atlas** (a collection of maps); the older code used "vault" (Obsidian's term). `UserDefaults` keys and the on-disk dev-data path retain the legacy "vault" string for backward compatibility, but everything else — types, properties, UI strings — is "atlas".

---

## Status

**Near-beta — prepping for TestFlight.** All three targets debug + release
green, release-build performance solid through hundreds of nodes / thousands
of edges on the heritage atlas. Currently in fit-and-finish for the v1
TestFlight cut. Foundation Models AI features require macOS 26 / iOS 26.

- **TerraCognita-macOS** — macOS 14+ `.app`, hardened runtime + app-sandbox
  entitlement (mic + user-selected files + app-scope bookmarks) for App
  Store / TestFlight eligibility
- **TerraCognita-iOS** — iPhone + iPad universal, iOS 17+
- **TerraCognita** — SwiftPM exec for the fastest dev loop on macOS (`swift run TerraCognita`)

### What's shipped

**Canvas & rendering**
- SwiftUI `Canvas` renderer (~300 nodes / ~1000 edges idle-smooth at 20 Hz)
- **Five layout algorithms** selectable from a toolbar menu:
  Force-directed (background FA2 solver), Circular, Radial
  (concentric BFS from selection), Hierarchical (BFS layers),
  Grid (deterministic √N × √N). Cluster is reserved for Phase 3
  (community detection).
- **No-overlap toggle** — optional iterative push-apart post-pass
  on any layout.
- **Smooth layout interpolation** — switching algorithms (or toggling
  no-overlap) eases every node from its current position to the new
  one via an explicit per-frame lerp (easeOutQuart over ~0.8 s)
  driven by the 20 Hz TimelineView, so the graph settles into the
  new arrangement instead of teleporting. Confirmed on the heritage
  atlas 2026-05-31. (SwiftUI's `withAnimation` doesn't animate
  values read inside a `Canvas`, hence the explicit interpolation.)
- Layout choice + no-overlap preference persist per-atlas.
- Era-driven **depth axis** with parallax-on-pan: older eras drift in
  the background, current era sits forward
- **Ambient drift** + **idle puff** so the field feels alive even when
  the user isn't interacting
- **Hover ring** (iPad pointer + Mac mouse) on the targeted node
- Persistent layout: node positions (including drag results) + scale
  + offset + algorithm + no-overlap survive relaunch
- Performance: smooth to ~1,500 nodes (see `scripts/stress_test.swift`);
  release builds run smoothly with the user's heritage atlas
  (hundreds of nodes, thousands of edges)

**Aesthetic**
- Deep-indigo → near-black radial gradient field, persistent across
  zoom levels
- **Type-color gradient edges** — each edge strokes a quadratic
  Bezier from source node color to destination node color. Endpoint
  opacity + saturation mirror the connected node so background-era
  endpoints fade like the nodes themselves. Curve direction is
  stable per edge (seeded by edge id) so reciprocal edges land on
  opposite sides.
- **Gold selection halo + orbital sparks + breath** distinct from
  the cooler ambient idle puff.
- **Pseudo-3D radial highlight** on foreground node discs — soft
  upper-left lit-from-above gradient lifts in-highlight, ambient,
  and selected nodes off the substrate. Dimmed background nodes
  stay flat (they're meant to recede).
- **Capsule label pills** — dark grey universal, gold-tinted on the
  selected node. Text at ~82% warm white.
- **Zoom-coupled node radii** — sqrt(scale) curve clamped to
  [0.55, 1.9] so the canvas reads as a spatial field rather than
  an abstract flat graph. Hit-testing inherits the scaling so tap
  targets track the eye.
- **Label-wide hit area** — `nodeAt` does a second hit test using
  the drawn label pill's bounding rect, so taps on the visible
  text register even when the disc itself is small.
- **Full-screen `LoadingScreen`** at launch — deep blue gradient,
  signature glyph (gold core + orbital sparks), rotating cartographer
  caption, fades out only after the canvas has loaded *and* the
  FA2 layout pipeline has actually settled. Substrate matches the
  iOS launch storyboard color so there's no white flash between
  launch and SwiftUI.
- Depth-aware drop shadows on nodes.

**Atlas I/O**
- Loads any Obsidian-style markdown atlas — YAML front-matter as node
  attributes, `[[wikilinks]]` + Dataview `key:: [[target]]` as typed edges
- Bundled **Miyazaki demo atlas** ships with both app targets
- Open / Create New Atlas via folder picker; drag-folder-onto-canvas
  works on macOS and iPadOS Stage Manager
- Security-scoped bookmarks for cross-launch persistence
- Recent-atlases library (LRU-12)
- Read-only refusal on the bundled demo (creation routes through
  Create-New-Atlas)

**Navigation & focus**
- Lens picker: All / People / Concepts / Institutions / Events / Works /
  **Seamwalkers** (nodes whose neighbors span ≥ 2 subnets — a
  computed "bridge" lens) — lives on the global radial under
  Lens ▸ with live count badges
- **Subnet decomposition + dive-in**: hubs (degree ≥ 6) collapse their
  members at top level; the "Dive into [Hub]" pill enters them
- **Forward / back navigation** (⌘[ / ⌘]) over selection + subnet state
- **Find** (⌘F): fuzzy search with prefix / word-prefix / initials match
- Inspector show / hide independent of selection (⌘I)
- **Privacy toggle** (eye): nodes with `private: true` in front-matter
  drop out of canvas + search + edges when hidden — useful for
  screenshots
- **Backgrounded nodes are unclickable** — when a selection's
  highlight halo is in effect, taps on dimmed neighbors-of-neighbors
  fall through to "clear selection" instead of switching to them,
  honoring the spatial-first model
- **Hop-distance dial** (1–4) on both radials — sets how far the
  selection halo reaches; persisted per-atlas

**Node ingestion / authoring**
- **Unified `AddNodeSheet`** (⌘N / ⌘⇧N / global radial "Add node")
  — single adaptive sheet that replaces the old NodeComposer + 
  CaptureSheet split. Short label-shaped text saves a placeholder
  via `createNode`; longer text or pasted URLs run through the AI
  capture pipeline. URL paste fetches the page (Wikipedia REST for
  `wikipedia.org`, HTML strip for everything else) and feeds the
  same capture pass.
- **Unified `AugmentNodeSheet`** — mirror surface for existing
  nodes. Paste/dictate context for a single node and the AI proposes
  body merges, new wikilinks, new linked nodes, era suggestion.
  The 8 named operations live as quick-action chips inside this
  sheet. Replaces the previous operations row in the inspector
  with a single "Augment this node…" button.
- **Long-press empty canvas → "Create node here"** — spatial drop-in
  creation with the spawn point captured in world coordinates and
  auto-framed
- **Inline note editing** — pencil icon in the Inspector's Note
  section opens a TextEditor seeded with the current body. Save
  (⌘S) writes through `AtlasEditor.replaceBody`; Cancel discards.
  Materializes a fresh file if the node is in-memory-only.
- **Mic-driven dictation** everywhere — Add Node, Augment Node,
  Genesis Chat, inspector edit mode. On-device
  (`SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`).
- Compose-time dedup — normalized-slug collisions block the write and
  offer "Open existing / Rename"
- **Inspector ⋯ menu** — Delete this node (with `.bak` snapshot) and
  Merge into… (atlas-wide `[[loser]] → [[winner]]` rewrite, body
  append, edge re-targeting)
- **Duplicate-cluster banner** on atlas load with one-click merge review

**Atlas Genesis (Phase A)**
- Chat-driven atlas creation embedded in the New Atlas template
  picker. Describe the atlas in plain English; the on-device AI
  extracts a starter constellation of typed, bodied, linked nodes;
  per-node accept/reject toggles let you shape it before commit.
- Auto-creates at `~/Documents/Terra Cognita Atlases/<Template> Atlas/`
  with ISO timestamp suffix on collision — no folder picker, no
  ceremony.
- Foundation Models availability banner up front so unavailable
  models don't produce silent "got nothing" outcomes.
- See [`GENESIS.md`](GENESIS.md) for the multi-phase plan
  (B/C/D/E).

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
- Read-only atlas refusal — the `+` and **Capture** buttons stay
  disabled until a writable atlas is open
- All speech recognition strictly on-device

**Radial menus (spatial action surface)**
- **Per-node radial** on long-press of a node — Open · AI ▸ · Edit ▸ ·
  Center · Hops ▸. AI submenu = Suggest connections / Find links /
  Suggest era / Concepts / Rewrite. Edit submenu = Type / Era / Body
  (opens TextEditor) / Merge… / Delete. Hops submenu = 1 / 2 / 3 / 4
  with the active value ✓-badged.
- **Global radial** on long-press of empty canvas — Add ▸ (Capture /
  New node here / Recipe) · Layout ▸ (all seven algorithms + the
  No-overlap toggle, active rows ✓-badged) · Lens ▸ (All / per-type
  with count badges / Systems) · View ▸ (Inspector toggle / Private
  toggle / Fit to window / Hops ▸).
- The toolbar collapsed accordingly to five high-frequency items:
  Back · Forward · Mode pill · Atlas menu · Find · Inspector toggle.
  Keyboard shortcuts ⌘N / ⌘⇧N / ⌘0 are preserved via invisible catchers.

**Edge editing & creation**
- **Spatial Connect mode** — long-press a node → radial → "Connect"
  wedge arms the source. Tap any node to create the edge; tap empty
  canvas to spawn a new node already wired to the source (opens
  `AddNodeSheet` seeded with a wikilink). Gold rubber-band overlay
  tracks source → hover target as you sweep. macOS power-user
  accelerator: shift+drag from a node.
- **Inspector + pills on Outbound / Inbound section headers** —
  list-based target picker for adding edges. Tap + → search-pick
  a target. Outbound writes the wikilink into the current note;
  Inbound writes it into the picked node's body (inbound edges
  live in the source).
- Outbound rows in the inspector are live: the relationship pill
  is a tappable Menu (atlas's known relationship types + Clear),
  and a trailing trash icon removes the edge. Edits rewrite the
  source note's Dataview line in place; prose-embedded wikilinks
  are left untouched with a friendly refusal.
- Inbound rows stay read-only (the source note is a *different*
  inspector's job).
- Duplicate prevention: same source / target / relationshipType
  triple is refused at `createEdge` with an "Already linked to X"
  status.

**Cross-platform parity**
- Same affordances across all three platforms; adaptations only where
  the platform demands them
- Sheet vs side-panel inspector based on size class
- Pinch zoom + single-finger pan (touch) and scroll-wheel +
  middle-mouse drag (macOS)
- Radial menus work identically on macOS, iPad, iPhone
- Haptics on iOS (selection, subnet enter/exit, proposal accept)
- App icon (Terra Cognita orrery) rendered by `scripts/render_icon.swift`

### Known issues

- **iOS — merge-duplicate-cluster doesn't persist across launches.** In
  the current session the merge runs and the banner clears, but the
  duplicate is back on relaunch. Suspected cause: the merge's file
  writes / deletes inside `GraphStore.mergeNode` use `try?` (silent
  failures) without an `NSFileCoordinator` wrap, so iOS sandbox /
  Files-app providers can reject the writes invisibly. Fix queued.
  See `BUGS.md`.

### What's still missing / rough

See [`PLAN.md`](PLAN.md) for the phased roadmap. Headline gaps:

- **Modes & launch templates** (Phase 2) — currently the app is
  Continuity-only; Worldbuild + Project Archaeology and their
  templates (Heritage / Reflective Journal / Career Map / Story
  Bible / World Bible / Concept Explorer / Code Repo / etc.) are
  the next push.
- **Timeline / Radial / Systems lenses** (Phase 3) — Lens system
  ships type-filter today; visual treatments and the topology
  (community / bridge) lens land in Phase 3.
- **Cluster layout** (Phase 3) — gated on community detection
  landing in `GraphAnalysis.swift`.
- **Import Recipes** (Phase 3) — NL → schema → deterministic
  executor for Markdown Atlas + Code Repo importers.
- **Display Settings panel** (Phase 3.5) — surface edge / pill /
  gradient constants the user has been driving via taste.
- **Live atlas watch** — external edits to .md files don't show
  until next atlas load.
- **Edge provenance UI** — `Provenance` (7 categories) and `era` /
  `date` on edges remain model-only. Spatial Connect + inspector
  + pills shipped the *creation* side; the rich-fields editor for
  existing edges is still TODO.
- **No 3D mode** — DESIGN.md's time-as-depth idea is hinted at via
  the parallax axis but not realized as a separate mode.
- **Capture review is modal** — a *spatial preview* (proposed nodes
  appear translucent on the canvas before commit) would feel even
  more like dive-in.
- **No graph-wide AI** — operations are all per-node; "Ask Terra
  Cognita" across the whole graph would be the next step.
- **Layout is O(n²)** for force-directed — Barnes-Hut would be the
  unblock past ~2,000 nodes.

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

### Top bar (collapsed)
| Action                   | Affordance                                        |
|--------------------------|---------------------------------------------------|
| Back / Forward           | Chevrons · ⌘[ / ⌘]                                |
| Mode pill                | Current mode (Continuity / Worldbuild / Archaeology) |
| Atlas menu               | Folder icon → Open / Create New / Recent / Import GEXF / Import Recipe / Settings |
| Find                     | Magnifier · ⌘F                                    |
| Show/hide info panel     | Sidebar · ⌘I                                      |

### Radial menus (long-press)
Lens, Add, Layout, Fit, Privacy, and the per-node actions all live on radial wheels:

| Wheel | Trigger | Wedges |
|-------|---------|--------|
| **Per-node radial** | Long-press a node | Open · AI ▸ · Edit ▸ · Center · Hops ▸ |
| └ AI ▸ | | Connections · Find links · Suggest era · Concepts · Rewrite |
| └ Edit ▸ | | Type · Era · Body · Merge… · Delete |
| └ Hops ▸ | | 1 · 2 · 3 · 4 (active ✓-badged) |
| **Global radial** | Long-press blank canvas | Add ▸ · Layout ▸ · Lens ▸ · View ▸ |
| └ Add ▸ | | Capture · New node here · Recipe |
| └ Layout ▸ | | Force · Circular · Radial · Hierarchical · Grid · Cluster · Timeline · [✓ No-overlap] |
| └ Lens ▸ | | All · per-type (with count badges) · Systems |
| └ View ▸ | | Inspector · Private · Fit · Hops ▸ |

⌘N (New Node), ⌘⇧N (Capture), and ⌘0 (Fit) still work via invisible keyboard-shortcut catchers.

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
│   │   ├── GraphView.swift              — Top-level view; body; sheet mounts; lifecycle
│   │   ├── GraphView+Radial.swift       — Per-node + global radial action builders
│   │   ├── GraphView+Chrome.swift       — canvasStack / topBar / atlasMenu / banners
│   │   ├── GraphCanvasView.swift        — Canvas renderer; gestures; layout pipeline
│   │   ├── GraphStore.swift             — @MainActor graph state; atlas I/O; ingestion
│   │   ├── NodeInspectorView.swift      — Inspector struct + body + helpers
│   │   ├── NodeInspectorView+Header.swift — Title row + type/era pickers + merge sheet
│   │   ├── NodeInspectorView+Note.swift — Note disclosure (read pane / edit + dictation)
│   │   ├── NodeInspectorView+Edges.swift — Outbound/Inbound lists + relationship menu
│   │   ├── NodeInspectorView+AI.swift   — AI section + operations + proposals + chat
│   │   ├── NodeIntelligence.swift       — Foundation Models orchestration
│   │   ├── AddNodeSheet.swift           — Unified add-node sheet (placeholder + capture + URL paste)
│   │   ├── AugmentNodeSheet.swift       — Unified augment-existing-node sheet (chips + paste)
│   │   ├── AtlasGenesisChat.swift       — Phase-A genesis chat embedded in template picker
│   │   ├── LoadingScreen.swift          — Full-screen launch surface (gradient + signature glyph)
│   │   ├── Constellation.swift          — Capture proposal model
│   │   ├── NodeProposal.swift           — Per-op AI proposal model
│   │   ├── NavigationHistory.swift      — Back/forward stack
│   │   ├── RadialMenu.swift             — Long-press action wheel (nested submenus)
│   │   ├── ForceDirectedLayout.swift    — Background FA2-ish solver
│   │   ├── LayoutEngine.swift           — Radial / Hierarchical / Grid + no-overlap
│   │   ├── LayoutAlgorithm.swift        — Enum of layout choices (+ SF symbols)
│   │   ├── LayoutPersistence.swift      — Per-atlas layout snapshots + hop dial
│   │   ├── Mode.swift                   — Mode enum (Phase 0 — single .continuity)
│   │   ├── GraphAnalysis.swift          — Stub for Phase 3 topology utils
│   │   ├── FolderPicker.swift           — iOS UIDocumentPickerViewController wrapper
│   │   ├── Era.swift                    — Era taxonomy + depth derivation
│   │   ├── AtlasLoader.swift            — Markdown atlas → Graph (+ Diagnostics)
│   │   ├── AtlasWriter.swift            — New-note creation + slug
│   │   ├── AtlasEditor.swift            — In-place note edits + .bak safety
│   │   │                                 + edge-line surgery (parse / rewrite)
│   │   ├── AtlasBookmark.swift          — Active-atlas security-scoped bookmark
│   │   ├── AtlasLibrary.swift           — Recent-atlases LRU
│   │   ├── AtlasDropHandler.swift       — Folder drag-drop onto canvas
│   │   ├── URL+SecurityScope.swift      — `url.withSecurityScope { ... }` helper
│   │   ├── WebEnrichment.swift          — Wikipedia REST summary client
│   │   ├── SpeechRecognizer.swift       — On-device SFSpeechRecognizer wrapper
│   │   ├── NodeSearchView.swift         — ⌘F popover
│   │   ├── MarkdownView.swift           — WKWebView markdown renderer (fallback)
│   │   ├── MarkdownBodyView.swift       — Native SwiftUI markdown for inspector
│   │   ├── Haptics.swift                — Cross-platform haptic shim
│   │   ├── Node.swift / Edge.swift / Provenance.swift — Domain types (+ isSynthetic)
│   │   ├── Node+File.swift              — Bundle URL lookups
│   │   ├── WebView+FileURL.swift        — Cross-platform open-in-default-app
│   │   └── Resources/miyazaki-vault/    — Bundled demo atlas (folder name preserved)
│   ├── TerraCognita/                    — Dev exec @main shell
├── Tests/
│   └── TerraCognitaKitTests/   — 47 tests across 6 suites (parsers,
│                                  editors, integration round-trips)
├── Data/heritage-vault/         — Personal heritage atlas (the dev dataset)
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
| Atlas I/O (load, create, recent)      | **~90%** — only missing live filesystem watch |
| Node ingestion (manual + AI)          | **~90%** — composer, long-press, dedup, Capture flow with voice + Wikipedia all in |
| AI integration (per-node ops)         | **~90%** — 8 ops + chat; missing graph-wide "Ask Terra Cognita" |
| AI integration (graph-wide / agentic) | **~10%** — Tool-protocol support and cross-atlas AI yet to come |
| Lens system                           | **~70%** — six lenses live; provenance-driven and saved-view lenses still to come |
| Edge editing & provenance UI          | **~50%** — relationship-type edit + delete shipped; add-edge target picker still TODO; `Provenance` + `era`/`date` still model-only |
| Navigation & focus management         | **~95%** — forward/back, inspector toggle, subnet dive, ESC exits, ⌘F find, hop-dial 1–4 |
| Cross-platform parity                 | **~95%** — macOS / iPad / iPhone all shipping the same features |
| Performance (large graphs)            | **~60%** — O(n²) layout, comfortable to ~1,500 nodes; Barnes-Hut needed beyond ~2,000 |
| 3D / time-as-depth mode               | **~5%**  — hinted at via parallax; nothing standalone |
| Tests / CI                            | **~30%** — 47 tests pin the parsers (`MarkdownNoteParser`, `AtlasEditor.parseEdgeLine` / `rewriteEdgeLine` / `splitFrontMatter` / `upsertFrontMatter`) and editor / loader integration. Run with `swift test`. View-layer + canvas-render still uncovered. |

Headline read: **MVP-feature-complete for personal use** on a graph of
up to a couple thousand nodes, with the spatial + AI ergonomics that
make it feel like a workbench rather than a viewer. Shipping at scale
(thousands of nodes, multi-user collaboration, edge-provenance editing,
saved lenses, agentic AI) is the next horizon.

---

## Roadmap

See [`PLAN.md`](PLAN.md) for the phased plan. Short version:

- **Phase 0** *(landed)* — foundations: `Mode` enum, `LayoutAlgorithm`,
  era/date metadata on `Edge`, `GraphAnalysis` placeholder.
- **Phase 1** *(landed)* — Layout selector with seven algorithms +
  No-overlap toggle.
- **Phase 2** *(landed)* — Modes + launch templates (3 modes,
  8 templates, mode pill, mode-aware defaults).
- **Phase 3** *(landed)* — Lens expansion (Timeline / Radial /
  Systems with bridge-node halos) + Import Recipes (NL → typed
  schema → deterministic executor) + Cluster layout.
- **Phase 3.7** *(landed)* — Radial menu expansion (per-node and
  global wheels) + toolbar collapse + hop-distance dial.
- **Phase 4** *(in progress)* — Hygiene, tests, design vocabulary
  gaps. Landed so far: 4.1 hygiene primitives (`URL.withSecurityScope`,
  `Edge.isSynthetic`, `ActiveSheet` enum, `SnapshotTracker`),
  4.1.5 Vault→Atlas rename, 4.2 test target (47 tests + 2 real
  bugs caught), 4.3a/b view-layer extraction
  (`NodeInspectorView+*.swift`, `GraphView+*.swift`).
  Remaining: 4.3c `CanvasPainter` namespace, 4.3d `AtlasSession`
  actor, then 4.4 (per-atlas edge-type taxonomy, add-edge UI,
  continuity threads, conversation-with-archive, Display Settings
  panel).
- **Phase 5** *(later)* — Pro tier: sync, cloud AI augmentation,
  large-graph background workers. Pro never gates data access.

**v1.1 (post-TestFlight) — audio identity layer.** Three-layer audio
design lined up for after v1 ships silent. Chime sonification ships
first as the identity piece: on node selection, chimes ring per
connected node, with pitch derived from connected-node type/color,
sequence from on-screen position, timbre from edge `relationshipType`,
and spatial placement from on-screen X/Y — the AirPods spatial-audio
read of "where the structure is" is the killer feature. Per-Atlas
MusicKit binding (resume music when you reopen an atlas) ships
second; an ambient generative bed ships last or skips entirely.
Out of scope: voice control, TTS reading, music-creation tools,
non-MusicKit streaming integrations. Whole doc lives in chat history;
load-bearing decisions banked in agent memory under
`project_audio_design`.

Cross-cutting follow-ups regardless of phase: live atlas watch,
spatial Capture preview, graph-wide AI, Barnes-Hut layout,
3D time-axis mode.
