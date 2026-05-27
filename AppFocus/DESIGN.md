# Terra Cognita — Unified Design Document (v2)

## Purpose

This document defines the architecture, vocabulary, interaction philosophy, modes, lenses, and product direction of Terra Cognita.

Terra Cognita is **a local-first, graph-native semantic workspace**: an interactive map where the graph itself is the primary surface — navigable, editable, exploratory, and meaning-bearing — backed by a vault of plain markdown the user owns.

---

# Core Philosophies

## Graph-as-Work-Surface

The graph is not a visualization sidebar, a report, or a secondary representation. It is the workspace.

## Meaning Density

The system prioritizes meaningful structure, continuity, provenance, semantic coherence, and intentionality — over mass ingestion, engagement loops, recommendation sludge, or uncontrolled automation.

## Local-First Ownership

> Your graph is yours.

User data is local-first, exportable, inspectable, portable, and user-owned. AI-generated structure is provisional, reviewable, and **non-canonical until accepted** (see *Staging Layer*).

---

# Canonical Terminology

## Node
A semantic entity. Backed by one markdown file in the vault.

## Edge
A semantic relationship between two nodes. Optionally typed.

## Canonical Graph
The verified, accepted, meaning-bearing graph. Authoritative.

## Staging Layer
A subgraph of provisional AI proposals, persisted distinctly from the Canonical Graph. The constellation review pane in Capture is the user's window into this layer. Nodes/edges leave the Staging Layer in one direction only — toward the Canonical Graph, on explicit user acceptance.

## Continuity-bearing edge
An edge annotated with a date or era. Enables timeline traversal and continuity analysis.

## Bridge node
A node with edges spanning ≥2 distinct semantic clusters. Detected via community detection on the canonical graph; surfaced by the Systems lens.

## Seamwalker (working term — to define or hold)
A bridge node with high traversal centrality — i.e. a bridge that is also a frequently-traversed shortest path between clusters. Held until we commit to an operational definition.

## Lens
A view treatment over the current graph — palette, edge weighting, what gets emphasized. Lenses do not change the underlying data.

## Layout
A spatial arrangement of the current graph. Layouts don't change the data either; they change where nodes sit on the canvas.

## Traverse
Move through the graph by following edges. Selecting a node and walking its 1-hop neighborhood is the canonical traverse gesture.

---

# Modes

A **mode** is an entry point — it determines what kind of graph the user is building and what node types / templates / import recipes are available by default. Three modes:

## 1. Continuity Mode

Graphs about **lived continuity over time** — people, careers, stories, lineages.

**Default node types:** person, institution, event, work, concept, era.
**Continuity-bearing by default** — every node and edge can carry a date or era.

**User journey:**
1. User picks a launch template or opens an existing Continuity vault.
2. App seeds the canvas with the template's starter nodes and prompts for the first capture.
3. User captures (text/voice) → AI proposes a constellation into the Staging Layer → user accepts/rejects per-node.
4. Timeline lens reveals the temporal spine.

**Launch templates:**
- **Heritage** — personal influence archaeology (current Miyazaki demo)
- **Reflective Journal** — temporal self-observation, journals, photos
- **Career Map** — career continuity and pivot analysis
- **Story Bible** — character arcs, motifs, narrative continuity

---

## 2. Worldbuild Mode

Graphs about **fictional or conceptual terrain** — invented worlds, conceptual landscapes, transmedia lore.

**Default node types:** character, faction, place, myth, institution, theme, artifact.
**Spatial / relational over temporal** — continuity is optional, not assumed.

**User journey:**
1. Template seeds an empty or stub world.
2. User authors nodes on-canvas (long-press → spatial create) or via Capture for bulk ideation.
3. AI proposes thematic bridges between distant nodes; user accepts via Staging Layer review.
4. Radial lens centers on the protagonist / world-center.

**Launch templates:**
- **World Bible** — TTRPG / novel / transmedia setting
- **Concept Explorer** — external-topic seed: user names a topic, AI seeds the Staging Layer with a starter graph from web + on-device knowledge; user prunes into the canonical graph

---

## 3. Project Archaeology Mode

Graphs over **file / code / asset structures** — discovered topology, not authored.

**Default node types:** depend on importer (file, asset, texture, class, scene, shader, etc.).
**Hard topology dominant** — explicit references in source data.

**User journey:**
1. User points the importer at a folder (or uses a natural-language Import Recipe).
2. Deterministic importer scans, surfaces detected references into the Staging Layer.
3. User accepts the import or refines the recipe and re-runs.
4. Systems lens surfaces bottlenecks, dependency cycles, dead assets.

**Launch templates:**
- **Code Repo** — imports, includes, call graphs
- **Unreal Project** — asset GUID graph, level references
- **Houdini Project** — VEX, OP networks, dependencies
- **USD Stage** — layer composition, references, payloads
- **Markdown Vault** — wikilinks, frontmatter, backlinks

---

# Lenses

A lens is a view treatment over the current graph. Lenses compose with modes and layouts.

| Lens | What it surfaces |
|---|---|
| **Network** (default) | Standard node-edge view, type-colored |
| **Timeline** | Continuity-bearing edges as the spine; nodes positioned by date/era |
| **Radial** | Ego-network — selection at center, neighbors at concentric rings |
| **Systems** | Bridge nodes, bottlenecks, disconnected regions, dependency cycles |
| **3D Depth** *(experimental)* | Time becomes depth; semantic regions become terrain |

---

# Layouts

A layout is the spatial arrangement of nodes. Accessible from a dedicated **Layout** button on the toolbar — opens a menu listing layouts as icon + text rows.

| Layout | Icon (SF Symbol) | When it shines |
|---|---|---|
| **Force-directed** *(default)* | `point.3.connected.trianglepath.dotted` | General exploration; clusters emerge organically |
| **Circular** | `circle.dotted` | Equal-citizen views; no implicit hierarchy |
| **Radial / Concentric** | `target` | Selection at center, hops as rings |
| **Hierarchical** | `arrow.triangle.branch` | Trees, DAGs, dependency chains |
| **Grid** | `square.grid.3x3` | Auditing / catalog views; deterministic position |
| **Cluster** | `circle.grid.hex` | Community detection — clusters as visual groupings |

Layouts persist per-vault. Switching layout animates the camera and node positions in one easeInOut pass (~600ms) so the user keeps spatial memory through the transition.

---

# Source Archetypes

| Archetype | Examples | Produces |
|---|---|---|
| **Structural** | codebases, graph formats, markdown links, asset systems | hard topology |
| **Semantic** | notes, documents, PDFs, articles | soft topology |
| **Experiential** | photos, calendars, music libraries, project timelines | continuity topology |

Modes consume one or more archetypes. Continuity favors semantic + experiential; Worldbuild is mostly authored (semantic); Project Archaeology is mostly structural.

---

# Local Data Sources

Potential extraction from on-device sources:

- **Apple Notes** — recurring concepts, thematic clusters
- **Apple Photos** — recurring locations, collaborators, events, visual motifs, project eras
- **Local File Systems** — dependency graphs, asset lineage, project archaeology
- **Markdown Vaults** — backlink topology, recurring themes

All extraction is on-device, opt-in per source, and lands in the Staging Layer for review.

---

# Import Recipes

A user-authored, AI-interpreted, deterministically-executed import specification.

**Example:**

> "Import folder `/foo/bar/baz`. Link any texture (`.png`) whose normalized name is referenced in any asset file (`.asset`). Rank size by degrees of connection and label nodes by base name. Texture nodes are orange, asset nodes are blue."

## Workflow

1. User provides natural language instructions.
2. On-device AI parses into a structured Import Recipe (typed schema).
3. User reviews / edits the recipe.
4. Deterministic importer executes the recipe.
5. Results enter the Staging Layer for acceptance.

## Design Principle

> AI interprets. The importer executes deterministically.

This preserves trust, provenance, inspectability, and reproducibility. An Import Recipe can be saved, shared, and replayed.

---

# Apple Intelligence Integration

## Role

On-device semantic augmentation: cluster interpretation, continuity analysis, graph assistance, import recipe interpretation, web enrichment routing.

## Boundaries

Apple Intelligence may **never** silently redefine meaning, canonize inferred structure, or obscure provenance. All AI output lands in the Staging Layer.

## Appropriate AI Tasks

Summarize graph regions, suggest semantic labels, identify bridges, detect recurring themes, infer clusters, interpret import recipes, propose constellations from captured text/voice.

---

# Visual and Interaction Philosophy

The graph should feel **alive, exploratory, tactile, calm, semantically rich, visually readable** — rather than enterprise, dashboard-like, surveillance-oriented, or aggressively analytical.

Aesthetic anchors: deep indigo → black radial field, warm gold selection ("the illuminated point"), ~80% warm-white labels in dark pills, drop shadows that lift things off the field, ambient idle puffs (cool blue) distinct from active selection (gold).

---

# Product Direction

## Free Local Edition

- Full local graph storage, editing, traversal
- All modes and launch templates
- All lenses and layouts
- Local imports and exports (markdown, GEXF)
- On-device AI ops (Capture, suggest links, web enrichment via the system)
- Moderate graph sizes (target: 5,000+ nodes on iPhone, 25,000+ on Mac)

## Pro Edition

- Multi-device sync (iCloud, Google Drive)
- Cloud AI augmentation (larger models, batch ops)
- Large-graph layouts (50,000+ nodes via background workers)
- Advanced analytics dashboards
- Team-shared Staging Layers

## Guardrail

> **Pro gates orchestration and compute. Pro never gates data access, portability, or interoperability.** The vault is always fully usable in the Free edition. There is no path by which upgrading to Pro adds essential read/write capabilities to the user's own data.

---

# Long-Term Direction

Terra Cognita may evolve into a semantic topology engine, a continuity-aware graph environment, a project archaeology system, a concept exploration tool, and a worldbuilding surface — while remaining local-first, user-owned, provenance-aware, human-guided, and semantically coherent.
