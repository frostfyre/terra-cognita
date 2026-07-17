# Terra Cognita

A native Apple-platform workbench (macOS, iPad, iPhone) that treats a
heritage graph — a markdown atlas of people, events, institutions,
works, and concepts — as the primary work surface. Navigable,
queryable, AI-augmented, and meant to feel like *moving through a
place* rather than reading a document.

**Terra Cognita 1.0 has shipped on the App Store for iOS and macOS.**
Product site: [terra-cognita.app](https://terra-cognita.app/).

See [`DESIGN.md`](DESIGN.md) for the unified design document
(modes, lenses, layouts, vocabulary, product direction),
[`PLAN.md`](PLAN.md) for the phased implementation roadmap,
[`GENESIS.md`](GENESIS.md) for the multi-phase chat-driven
atlas-creation flow (Phases A–D landed), and
[`BUGS.md`](BUGS.md) for the issue log.
[`Design/DESIGN.md`](Design/DESIGN.md) is the older original vision
document and is kept for historical context.

**Anchors:** `mvp-1.0` tag = stable feature baseline; `visual-milestone-1.0` tag = the indigo-gradient + gold-selection + curved-gradient-edges aesthetic lock-in.

> Heritage note on naming: the user-facing word is **atlas** (a collection of maps); the older code used "vault" (Obsidian's term). `UserDefaults` keys and the on-disk dev-data path retain the legacy "vault" string for backward compatibility, but everything else — types, properties, UI strings — is "atlas".

---

## Status

**Shipped — v1.0 live on the App Store for iOS and macOS.** All three
targets debug + release green; release-build performance solid through
hundreds of nodes / thousands of edges on the heritage atlas, and an
order of magnitude beyond that on the Pro Metal renderer. Foundation
Models AI features require macOS 26 / iOS 26.

- **TerraCognita-macOS** — macOS 14+ `.app`, hardened runtime + app-sandbox
  entitlement (mic + user-selected files + app-scope bookmarks)
- **TerraCognita-iOS** — iPhone + iPad universal, iOS 17+
- **TerraCognita** — SwiftPM exec for the fastest dev loop on macOS (`swift run TerraCognita`)

### What's shipped

**Canvas & rendering**
- SwiftUI `Canvas` renderer, idle-smooth at 20 Hz, with viewport
  culling of off-screen nodes + edges in the render loop
- **Seven layout algorithms** selectable from the radial menu:
  Force-directed (background FA2 solver with a **Barnes-Hut quadtree**
  for repulsion above N=200), Circular, Radial (concentric BFS from
  selection), Hierarchical (BFS layers), Grid (deterministic √N × √N),
  Cluster (community detection), Timeline.
- **No-overlap toggle** — optional iterative push-apart post-pass
  on any layout.
- **Smooth layout interpolation** — switching algorithms (or toggling
  no-overlap) eases every node from its current position to the new
  one via an explicit per-frame lerp (easeOutQuart over ~0.8 s)
  driven by the 20 Hz TimelineView, so the graph settles into the
  new arrangement instead of teleporting. (SwiftUI's `withAnimation`
  doesn't animate values read inside a `Canvas`, hence the explicit
  interpolation.)
- Layout choice + no-overlap preference persist per-atlas.
- Era-driven **depth axis** with parallax-on-pan: older eras drift in
  the background, current era sits forward
- **Ambient drift** + **idle puff** so the field feels alive even when
  the user isn't interacting
- **Hover ring** (iPad pointer + Mac mouse) on the targeted node
- Persistent layout: node positions (including drag results) + scale
  + offset + algorithm + no-overlap survive relaunch
- Degree-scaled node radii (5–64 band) in both renderers

**Pro renderer (Terra Cognita Pro)**
- **Metal "bolt" renderer** — GPU-instanced draws for an
  order-of-magnitude fps gain on large atlases, with labels, halos,
  and hero images layered as SwiftUI overlays. Canvas-parity
  visuals including curved gradient edges.
- Toggled from the toolbar bolt button; device-wide preference.
- Unlocked by the app's single one-time in-app purchase via StoreKit,
  with an obvious, feedback-giving Restore Purchases flow.
- Honors the DESIGN.md guardrail: **Pro gates compute, never data** —
  the full atlas stays usable on the free Canvas renderer at any size.

**Audio (fully integrated)**
- **Chime sonification** — on node selection, chimes ring per
  connected node: pitch derived from the connected node's type/color,
  sequence from on-screen position, timbre from the edge's
  `relationshipType`, and stereo placement from on-screen X/Y — the
  spatial-audio read of "where the structure is."
- **Opt-in by design** — audio is off by default; a first-launch
  intro sheet presents the choice once, and a toolbar music-note
  control toggles it anytime. Global preference layered with
  per-atlas `audio:` config.
- **Per-atlas MusicKit soundtrack binding** — bind a playlist or
  album to an atlas from Atlas Settings via in-app catalog search
  (URL paste as fallback); it resumes when you reopen the atlas and
  handles atlas-switch and app-background lifecycle. Atlas-suggested
  soundtracks supported (the bundled Miyazaki demo suggests a Joe
  Hisaishi playlist).
- Plays under `.ambient` + `mixWithOthers`, so it coexists with
  whatever else is playing.

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
- **GEXF import** on both macOS and iOS, with types/lenses synced to
  the loaded network
- Bundled **Miyazaki demo atlas** ships with both app targets
- Open / Create New Atlas via folder picker; drag-folder-onto-canvas
  works on macOS and iPadOS Stage Manager
- Security-scoped bookmarks for cross-launch persistence;
  `NSFileCoordinator`-wrapped writes and deletes on iOS so
  Files-app-provider rejections surface as real errors
- Recent-atlases library (LRU-12)
- Read-only refusal on the bundled demo (creation routes through
  Create-New-Atlas)

**Modes & templates**
- Three modes (Continuity / Worldbuild / Project Archaeology) with a
  toolbar mode pill and mode-aware defaults
- Launch templates (Heritage / Reflective Journal / Career Map /
  Story Bible / World Bible / Concept Explorer / etc.) in the New
  Atlas template picker

**Navigation & focus**
- Lens picker: All / People / Concepts / Institutions / Events / Works /
  **Seamwalkers** (nodes whose neighbors span ≥ 2 subnets — a
  computed "bridge" lens) — lives on the global radial under
  Lens ▸ with live count badges, plus the Systems lens with
  bridge-node halos
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

**Atlas Genesis (Phases A–D)**
- Chat-driven atlas creation embedded in the New Atlas template
  picker. Describe the atlas in plain English; the on-device AI
  extracts a starter constellation of typed, bodied, linked nodes;
  per-node accept/reject toggles let you shape it before commit.
- **Multi-turn refinement** — a persistent session so follow-up
  messages extend the constellation in place ("go deeper on X",
  "add Y", "what's missing").
- **Per-node deep expansion** — tap the deepen icon on any proposed
  node and the AI drafts a richer body plus a sub-constellation of
  related people / works / concepts / events. Recursive.
- **Wikipedia enrichment** wired into the deepen + extend paths.
- Auto-creates at `~/Documents/Terra Cognita Atlases/<Template> Atlas/`
  with ISO timestamp suffix on collision — no folder picker, no
  ceremony.
- Foundation Models availability banner up front so unavailable
  models don't produce silent "got nothing" outcomes.
- See [`GENESIS.md`](GENESIS.md) for the phase docs.

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
  New node here) · Layout ▸ (all seven algorithms + the
  No-overlap toggle, active rows ✓-badged) · Lens ▸ (All / per-type
  with count badges / Systems) · View ▸ (Inspector toggle / Private
  toggle / Fit to window / Hops ▸).
- The toolbar collapsed accordingly to the high-frequency items:
  Back · Forward · Mode pill · Atlas menu · Find · Inspector toggle,
  plus the audio and Pro-renderer controls.
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

## Potential future features

Ideas that didn't make the 1.0 cut. None are commitments; they're the
directions the design points toward. See [`PLAN.md`](PLAN.md) and
[`DESIGN.md`](DESIGN.md) for the fuller sketches.

- **Import Recipes in the UI** — the NL → typed schema →
  deterministic executor pipeline is built and wired
  (`RecipeInterpreter` / `RecipeExecutor` / `ImportRecipeSheet`),
  but its entry points are hidden behind
  `GraphView.recipeImportEnabled` until the workflow has been
  exercised more.
- **Live atlas watch** — external edits to .md files currently don't
  show until the next atlas load.
- **Edge provenance UI** — `Provenance` (7 categories) and `era` /
  `date` on edges remain model-only; the rich-fields editor for
  existing edges is unbuilt.
- **Display Settings panel** — surface the edge / pill / gradient
  constants that are currently taste-driven hard-coded values.
- **3D time-as-depth mode** — DESIGN.md's idea is hinted at via the
  parallax axis but not realized as a separate mode.
- **Spatial Capture preview** — proposed nodes appearing translucent
  on the canvas before commit, instead of the modal review pane.
- **Graph-wide AI** — operations are all per-node today; "Ask Terra
  Cognita" across the whole graph would be the next step, along with
  tool-protocol / agentic AI and cross-atlas queries.
- **Saved-view and provenance-driven lenses** on top of the shipped
  lens system.
- **Ambient generative audio bed** — the third layer of the audio
  design; chimes and MusicKit binding shipped, the generative bed
  did not.
- **Sync & multi-user collaboration** — cloud sync, cloud AI
  augmentation, large-graph background workers. Pro will never gate
  data access.
- **View-layer test coverage** — 61 tests across 8 suites pin the
  parsers, editors, config reconcile, chime scale, and loader
  integration (`swift test`); canvas rendering and view-layer
  behavior remain uncovered.

---

## Build & Run

```bash
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
| Atlas menu               | Folder icon → Open / Create New / Recent / Import GEXF / Settings |
| Find                     | Magnifier · ⌘F                                    |
| Audio                    | Music note → chime toggle / soundtrack            |
| Pro renderer             | Bolt → Metal renderer toggle (Pro)                |
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
| └ Add ▸ | | Capture · New node here |
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
terra-cognita/
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
│   │   ├── Metal/                       — Pro "bolt" renderer (GraphMetalView,
│   │   │                                  GraphRenderer, shaders, SwiftUI overlays
│   │   │                                  for labels / halos / hero images)
│   │   ├── GraphStore.swift             — @MainActor graph state; atlas I/O; ingestion
│   │   ├── EntitlementStore.swift       — StoreKit Pro entitlement + product load
│   │   ├── PaywallSheet.swift           — Terra Cognita Pro purchase / restore sheet
│   │   ├── AudioEngine.swift            — AVAudioEngine chime playback (.ambient, mixes)
│   │   ├── ChimeSonifier.swift          — Selection → chime sequence mapping
│   │   ├── ChimeScale.swift             — Type/color → pitch scale
│   │   ├── AudioIntroSheet.swift        — First-launch audio opt-in
│   │   ├── AudioUserPreference.swift    — Global audio prefs (UserDefaults)
│   │   ├── MusicService.swift           — MusicKit playback + lifecycle
│   │   ├── MusicBindingPickerSheet.swift — In-app catalog search + URL paste binding
│   │   ├── MusicSuggestion.swift / MusicSuggestionPopover.swift — Atlas-suggested soundtracks
│   │   ├── NodeInspectorView.swift (+Header/+Note/+Edges/+AI) — Inspector
│   │   ├── NodeIntelligence.swift       — Foundation Models orchestration
│   │   ├── AddNodeSheet.swift           — Unified add-node sheet (placeholder + capture + URL paste)
│   │   ├── AugmentNodeSheet.swift       — Unified augment-existing-node sheet (chips + paste)
│   │   ├── AtlasGenesisChat.swift       — Genesis chat embedded in template picker
│   │   ├── AtlasGenesisDeepenSheet.swift — Per-node deep expansion (Phase C)
│   │   ├── Template.swift / TemplatePickerSheet.swift — Modes + launch templates
│   │   ├── ImportRecipe.swift / RecipeInterpreter.swift / RecipeExecutor.swift
│   │   │   / ImportRecipeSheet.swift    — Import Recipes (UI currently gated off)
│   │   ├── GEXFImporter.swift           — GEXF → Graph importer
│   │   ├── LoadingScreen.swift / LoadingCaptions.swift — Launch surface
│   │   ├── Constellation.swift          — Capture proposal model
│   │   ├── NodeProposal.swift           — Per-op AI proposal model
│   │   ├── NavigationHistory.swift      — Back/forward stack
│   │   ├── RadialMenu.swift             — Long-press action wheel (nested submenus)
│   │   ├── ForceDirectedLayout.swift    — FA2-ish solver + Barnes-Hut quadtree
│   │   ├── LayoutEngine.swift           — Radial / Hierarchical / Grid + no-overlap
│   │   ├── LayoutAlgorithm.swift        — Enum of layout choices (+ SF symbols)
│   │   ├── LayoutPersistence.swift      — Per-atlas layout snapshots + hop dial
│   │   ├── Mode.swift                   — Mode enum (Continuity / Worldbuild / Archaeology)
│   │   ├── GraphAnalysis.swift          — Community detection / topology utils
│   │   ├── AtlasLoader.swift            — Markdown atlas → Graph (+ Diagnostics)
│   │   ├── AtlasWriter.swift            — New-note creation + slug
│   │   ├── AtlasEditor.swift            — In-place note edits + .bak safety
│   │   │                                 + edge-line surgery (parse / rewrite)
│   │   ├── AtlasConfig.swift            — Per-atlas config (audio block etc.)
│   │   ├── AtlasSettingsSheet.swift     — Per-atlas settings incl. music binding
│   │   ├── AtlasBookmark.swift          — Active-atlas security-scoped bookmark
│   │   ├── AtlasLibrary.swift           — Recent-atlases LRU
│   │   ├── AtlasDropHandler.swift       — Folder drag-drop onto canvas
│   │   ├── URL+SecurityScope.swift      — `url.withSecurityScope { ... }` helper
│   │   ├── WebEnrichment.swift          — Wikipedia REST summary client
│   │   ├── HeroImageLoader.swift        — Node hero images
│   │   ├── SpeechRecognizer.swift       — On-device SFSpeechRecognizer wrapper
│   │   ├── NodeSearchView.swift         — ⌘F popover
│   │   ├── MarkdownView.swift / MarkdownBodyView.swift — Markdown rendering
│   │   ├── Haptics.swift                — Cross-platform haptic shim
│   │   ├── Node.swift / Edge.swift / Provenance.swift — Domain types (+ isSynthetic)
│   │   ├── AboutSheet.swift             — About / credits
│   │   └── Resources/miyazaki-vault/    — Bundled demo atlas (folder name preserved)
│   ├── TerraCognita/                    — Dev exec @main shell
├── Tests/
│   └── TerraCognitaKitTests/   — 61 tests across 8 suites (parsers,
│                                  editors, config reconcile, chime
│                                  scale, integration round-trips)
├── Products.storekit            — StoreKit config (Terra Cognita Pro IAP)
├── fastlane/                    — Release automation
├── index.html / join/ / privacy.html / support.html / Legal/ — terra-cognita.app site
├── Design/DESIGN.md             — Original vision document
└── scripts/
    ├── generate_xcodeproj.rb    — Project generator (xcodeproj gem)
    ├── render_icon.swift        — App icon (Terra Cognita orrery) renderer
    └── stress_test.swift        — Layout benchmark
```

---

## Roadmap

The phased plan in [`PLAN.md`](PLAN.md) is complete through 1.0:

- **Phase 0** *(landed)* — foundations: `Mode` enum, `LayoutAlgorithm`,
  era/date metadata on `Edge`, `GraphAnalysis` placeholder.
- **Phase 1** *(landed)* — Layout selector with seven algorithms +
  No-overlap toggle.
- **Phase 2** *(landed)* — Modes + launch templates (3 modes,
  8 templates, mode pill, mode-aware defaults).
- **Phase 3** *(landed)* — Lens expansion (Timeline / Radial /
  Systems with bridge-node halos) + Import Recipes engine + Cluster
  layout.
- **Phase 3.7** *(landed)* — Radial menu expansion (per-node and
  global wheels) + toolbar collapse + hop-distance dial.
- **Phase 4** *(landed)* — Hygiene primitives, Vault→Atlas rename,
  test target, view-layer extraction.
- **Phase 4.5** *(landed, A–D)* — Atlas Genesis: chat-driven creation,
  multi-turn refinement, per-node deepen, Wikipedia enrichment.
- **Phase 4.8** *(landed)* — TestFlight cut, then App Store release
  on iOS and macOS.
- **Phase 5** *(landed in part)* — Pro tier shipped as the Metal
  renderer IAP (compute, never data). Sync / cloud AI / background
  workers remain future ideas.
- **Audio identity layer** *(landed)* — chime sonification +
  per-atlas MusicKit binding, opt-in by default. The ambient
  generative bed is the one remaining layer (see Potential future
  features).

Everything else lives under **Potential future features** above.
