# Terra Cognita — Implementation Plan

Phased plan against `DESIGN.md` (v2). Ordering favors invisible plumbing first, then the highest-leverage user-visible work, then progressively larger structural shifts.

## Phase 0 — Foundations *(invisible to user)*

Lock terminology in code and lay groundwork so later phases compose.

- Add `Mode` enum with single `.continuity` case initially, so adding modes later doesn't require call-site churn.
- Add `era` / `date` metadata to `Edge.swift:1` so continuity-bearing edges become possible in Phase 3.
- Add a stub `GraphAnalysis` util (community detection skeleton, empty body) so Phase 3's Systems lens has a home.
- Rename `layoutKind` (`GraphCanvasView.swift:123`) → `LayoutAlgorithm` with the full enum the design calls for.

No user-visible change. Risk: low.

## Phase 1 — Layout Selector *(high visibility — user-requested)*

Ship the Layout button + menu (icon + text rows) with multiple algorithms.

- Implement four new algorithms alongside the existing force-directed: **Circular** (already exists, just expose), **Radial** (concentric from selection), **Hierarchical** (basic DAG / breadth layering), **Grid** (deterministic √N × √N).
- Defer **Cluster** until Phase 3 (needs community detection).
- Layout button in toolbar — `Menu` showing SF Symbol + label rows from the doc.
- Persist current layout per-vault (alongside scale/offset in `LayoutPersistence`).
- Animate transitions ~600ms easeInOut so spatial memory survives.

Risk: medium — the force-directed pipeline at `GraphCanvasView.swift:889–931` needs to gracefully hand off to deterministic layouts without fighting them.

## Phase 2 — Modes + Launch Templates

Where Terra Cognita stops being heritage-only.

- Promote `Mode` enum to the 3 modes; add a `ModePicker` at vault creation + a discreet pill in the toolbar showing the current mode.
- **Template registry**: each launch template = `(Mode, name, icon, seedClosure(vaultURL))`. `VaultWriter.initializeEmptyVault` at `VaultWriter.swift:64` learns to take a template.
- Wire up Continuity templates (Heritage / Reflective Journal / Career Map / Story Bible) and Worldbuild templates (World Bible / Concept Explorer); Project Archaeology templates land in Phase 3.
- Mode-aware defaults: default node types, default lens, default layout.

Risk: medium — schema migration for older vaults that have no mode tag (default to Continuity).

## Phase 3 — Lens Expansion + Import Recipes

The "Terra Cognita is a real workshop" phase.

- **Timeline lens** — uses the new edge dates from Phase 0.
- **Radial lens** — visual treatment (palette + concentric rendering) separate from Radial layout.
- **Systems lens** — Louvain or label-propagation community detection; bridge nodes highlighted; bottlenecks surfaced. Backs the deferred Cluster layout too.
- **Import Recipes**: NL → typed schema (FoundationModels structured generation) → deterministic executor. Two importer backends to start: Markdown Vault (richer than today's loader — actual link graph) and Code Repo (Swift/Python import graph). GEXF stays as-is.

Risk: medium-high — community detection on large graphs needs a background worker.

## Phase 3.5 — Display Settings panel *(later)*

Surface canvas appearance controls the user has so far set via taste-driven hard-coded constants: edge line width, edge opacity, edge curve amount, label pill opacity, gradient endpoints, ambient puff frequency. A single settings sheet (gear icon in the toolbar) writes preferences to `UserDefaults` and the canvas reads from a `DisplaySettings` observable. Order this against Phase 3 work — likely natural to land after Lens expansion.

## Phase 3.7 — Radial menus expansion *(shipped)*

Toolbar real estate is saturated (10+ controls). The existing per-node
`RadialMenu` already proves the spatial-context pattern works on
canvas; extend it to a complete app-control surface and collapse the
toolbar to just the genuinely-high-frequency items.

**Foundation** — `RadialMenu.Action` gains an optional `children:
[Action]?`. Wedges with children push the wheel to a sub-menu;
center button becomes a back-arrow + parent label. Sub-menu state
lives inside the menu view, so callers still pass a single flat
top-level `[Action]` plus nested children.

**Global radial** (long-press empty canvas — extends the current
"create node here" affordance):

- **Add** → Capture, New Node here, Import Recipe
- **Layout** → Force / Circular / Radial / Hierarchical / Grid /
  Cluster / Timeline / [✓ No-overlap]
- **Lens** → All / [each type] / Systems (with count badges)
- **View** → Toggle inspector, Toggle private, Fit to window,
  **Hops** sub-radial (1 / 2 / 3 / 4)
- Cancel (center)

**Per-node radial** (long-press a node — extends the current wheel):

- **Open / Inspect**
- **AI** → Suggest connections, Find links, Suggest era, Summarize,
  Rewrite
- **Edit** → Type, Era, Body, Delete, Merge into…
- **Center / Frame**
- **Hops** → 1 / 2 / 3 / 4 (same dial as global View → Hops; touch
  the current selection's highlight depth immediately)
- Cancel (center)

**Hop-distance dial**: promotes today's hard-coded
`private let highlightDepth = 1` to per-vault state persisted in
`LayoutPersistence`. Reachable from BOTH the per-node radial
(immediate apply) and the global View radial (default for future
selections). Different vault densities want different hops.

**Toolbar after collapse** (4–5 items, all high-frequency):
Back / Forward · Mode pill · Vault menu · Find · Inspector toggle.

Wonky things to settle as we land each piece:

- Toggle wedges (No-overlap, Privacy) need a visible checked state —
  ✓ badge on the wedge fill.
- Lens count badges ("Concepts (45)") — preserve from the existing
  Menu in the radial layout.
- Mode pill stays in the toolbar (pure-display, fits chrome).
- Two entry points for Hops is intentional: per-node = "this one
  expanded", global = "default for future selections".

**Shipped status** — all four sub-items in this phase landed:
nested `RadialMenu.Action`, per-node radial with AI/Edit/Hops
submenus, global radial on long-press blank canvas, and the
toolbar collapse to Back/Forward · Mode · Vault · Find · Inspector.
Keyboard shortcuts ⌘N / ⌘⇧N / ⌘0 are preserved via invisible
catchers in `canvasStack`. Hop-distance dial (1–4) is persisted
per-vault in `LayoutPersistence`.

## Phase 4 — Pro Tier *(later)*

Sync (iCloud first), cloud AI augmentation, large-graph background workers, team-shared Staging Layers. Don't start until 1–3 are tight and we have user signal.

---

## Open calls before cutting code

1. **Mode picker placement** — full-screen "what kind of graph?" on first vault create, or always-visible toolbar selector? Recommendation: first-time only at creation, then a discreet pill in the toolbar that shows current mode and tap-to-switch.
2. **Mode-vs-template granularity** — do we let the user change a vault's mode after creation, or is it set-once? Recommendation: changeable, but warn if existing nodes don't match the new mode's default types.
