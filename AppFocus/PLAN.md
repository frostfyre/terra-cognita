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

## Phase 4 — Pro Tier *(later)*

Sync (iCloud first), cloud AI augmentation, large-graph background workers, team-shared Staging Layers. Don't start until 1–3 are tight and we have user signal.

---

## Open calls before cutting code

1. **Mode picker placement** — full-screen "what kind of graph?" on first vault create, or always-visible toolbar selector? Recommendation: first-time only at creation, then a discreet pill in the toolbar that shows current mode and tap-to-switch.
2. **Mode-vs-template granularity** — do we let the user change a vault's mode after creation, or is it set-once? Recommendation: changeable, but warn if existing nodes don't match the new mode's default types.
