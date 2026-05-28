# Graph Workbench App Design

## Vision

A native macOS / iOS application designed to treat the heritage graph itself as a primary work surface.

The application is intended as:
- an interactive heritage map
- a thought engine
- a lineage exploration environment
- a provenance-aware semantic graph
- a continuity-mapping system
- and a personal navigation instrument.

Markdown files remain the canonical backing store, while the graph becomes the primary interaction model.

---

# Core Principles

## The Graph is the Interface

The graph is not a side panel or visualization.

It is:
- navigable
- queryable
- editable
- inspectable
- semantically meaningful
- and capable of becoming ambient infrastructure.

Users should be able to think spatially through lineage and relationship.

---

## Provenance Matters

The system should distinguish between:
- direct influence
- verified lineage
- institutional connection
- inferred affinity
- recommendation
- adjacency
- speculation

Edges should support provenance metadata and confidence levels.

---

## Meaning Density Matters

The graph should resist:
- recommendation sludge
- low-signal ingestion
- semantic flattening
- uncontrolled automation
- productivity-software drift
- engagement optimization

The graph should feel:
- cultivated
- deliberate
- semantically dense
- and meaningful.

---

# AI Philosophy

## Local-First Intelligence

The system should prioritize:
- privacy
- inspectability
- provenance preservation
- deterministic ownership
- local semantic reasoning

The heritage graph itself should remain:
- human-authored
- provenance-aware
- locally stored
- and inspectable.

AI should assist understanding, not replace authorship.

---

## Apple Intelligence as Default AI Layer

Primary interactive AI should use:
- Apple Intelligence
- Apple Foundation Models
- on-device inference where possible

Reasons:
- private local execution
- native Swift integration
- offline capability
- no API costs
- semantic reasoning over local graph data

The on-device model should primarily reason over:
- markdown nodes
- graph metadata
- lineage relationships
- subnet structure
- semantic context

rather than internet-scale world knowledge.

---

## Appropriate AI Tasks

Apple Intelligence should support:
- natural-language graph queries
- node summarization
- relationship explanation
- metadata extraction
- semantic search
- tag suggestion
- subnet analysis
- edge candidate suggestions
- provenance-aware prompts

External/cloud AI may optionally support:
- research
- exploratory lineage discovery
- large-context synthesis

But:
- external AI should never silently modify the graph
- provenance must remain explicit
- suggested nodes/edges require human approval

---

# Graph-Native Interaction

## Relationship-First Design

Unlike traditional note systems:
- documents are not the primary abstraction
- relationships are.

Notes become:
- evidence
- annotations
- semantic anchors
- contextual artifacts
- manifestations of continuity

The underlying substrate is:
- nodes
- edges
- provenance
- semantic distance
- temporal layering
- meaning accumulation

---

## Invisible Graph Support

The graph does not always need to be visible.

In many modes the graph should instead manifest as:
- contextual navigation
- semantic neighborhoods
- radial menus
- lineage suggestions
- pathfinding
- adaptive interfaces
- temporal clustering
- relationship-aware interaction

The graph becomes:
- ambient semantic infrastructure.

---

# Surface Modes

## Explicit Graph Mode
Used for:
- exploration
- clustering
- archaeology
- subnet discovery
- lineage tracing

## Focused Semantic Mode
A calmer reading/thinking interface with:
- contextual graph augmentation
- semantic side channels
- invisible relationship support

## Temporal Mode
Supports:
- influence waves
- time-depth exploration
- developmental mapping
- continuity replay
- career-era analysis

## Systems Mode
Highlights:
- seamwalkers
- bridge nodes
- category overlaps
- semantic load-bearing structures

## Reflective Mode
Supports:
- journaling
- recurrence analysis
- continuity detection
- self-understanding
- pattern surfacing

---

# Platform Direction

## Native Platforms
- macOS
- iOS
- potentially iPadOS-first interaction

## Recommended Technologies
- SwiftUI
- Metal
- SceneKit or SpriteKit
- SQLite local cache/index
- Markdown atlas as source of truth
- GEXF import/export
- Obsidian-compatible wikilinks
- Apple Foundation Models framework

---

# Core Interface

## Graph Canvas

Primary interaction surface.

Capabilities:
- pan
- zoom
- cluster
- subnet extraction
- expand/collapse neighbors
- path tracing
- dynamic filtering
- lens application
- graph coloring
- graph sizing

Visual controls:
- node size by degree/PageRank/custom metric
- color by media/domain/lineage
- edge styling by provenance
- animated traversal paths
- pinned nodes
- focus mode

---

## Node Inspector

Displays:
- markdown body
- metadata
- media tags
- lineage notes
- provenance
- inbound/outbound links
- edge explanations
- relationship evidence

Supports inline editing.

---

## Query / Lens Panel

Supports:
- semantic filtering
- graph queries
- lineage extraction
- saved lenses
- subnet exploration

Example queries:
- show all direct visual influences connected to games
- trace Frazetta to Blizzard
- show all seamwalker candidates
- show AI and identity related nodes

---

# Lens System

A lens is a semantic view over the graph.

## Example Lenses
- Artistic Lineage
- Seamwalkers
- Simulation-Native Worlds
- Personal Contacts
- Institutional History
- AI / Identity / Embodiment
- Cozy Mythic Ecology
- Technical Art Lineage
- Motion Capture History
- PlayStation Era

Lenses may:
- recolor nodes
- filter edges
- modify metadata visibility
- change layout behavior
- prioritize subnet expansion

---

# Graph Layouts and Spatial Modes

Layouts should function as thinking tools, not merely visual styles.

## Core 2D Layouts
- force-directed
- radial
- hierarchical
- timeline
- matrix/grid
- institutional/geographic

---

# 3D Representation

A 3D graph mode should be explored as an optional spatial work surface.

Core concept:
- time becomes the depth axis

Suggested axes:
- X = semantic/domain similarity
- Y = influence intensity or category grouping
- Z = time

Time may represent:
- historical chronology
- first personal encounter
- career eras
- conceptual depth

The most meaningful default may be:
- when a node entered the user's life or became influential.

3D should remain optional and meaning-oriented rather than spectacle-oriented.

---

# Default Visual Language

## Primary Default Mode

The default experience should open into:
- a 2D network representation
- lightly animated
- visually alive
- calm and readable
- tactile and responsive

The graph should feel:
- exploratory
- dynamic
- curious
- and emotionally inviting

rather than:
- sterile
- aggressively technical
- or enterprise-oriented.

---

# Motion Philosophy

Animation should communicate:
- continuity
- relationship
- emergence
- attention

rather than spectacle.

Recommended motion:
- subtle node drift
- spring interactions
- soft settling
- smooth expansion/collapse
- hover pulse effects
- animated path tracing
- inertial pan/zoom

---

# Visual Palette System

Palettes should affect:
- node colors
- edge colors
- glow intensity
- typography contrast
- background treatment
- animation tone

Suggested palette families:
- Neutral / Research
- Painterly
- Cybernetic
- Cozy Mythic
- Systems / Simulation

---

# Interaction Design

## Contextual Radial Menu

Primary contextual interaction model.

Desktop:
- right click

Mobile:
- press and hold

### Node Actions
- Open note
- Expand neighbors
- Collapse neighbors
- Pin node
- Focus subnet
- Trace lineage
- Add relationship
- Change edge type
- Mark provenance
- Hide unrelated nodes

### Edge Actions
- Inspect relationship
- Edit relationship type
- Set confidence
- Attach evidence

### Canvas Actions
- Add node
- Add relationship
- Run query
- Apply lens
- Export subnet
- Reset view

---

# Import / Interchange Strategy

The app should support ingestion from:
- graph formats
- table formats
- mind maps
- markdown atlases
- semantic exports
- structured datasets

Supported examples:
- GEXF
- GraphML
- CSV
- XLSX
- OPML
- FreeMind
- Obsidian atlases
- Logseq
- JSON graph formats

Imports should enter a staging layer before promotion into the canonical heritage graph.

---

# Canonical Graph Philosophy

The system should maintain:
- a canonical heritage graph
- optional live semantic layers
- staging/suggestion layers
- provenance-aware imports

Live connections should augment understanding, not silently rewrite meaning.

---

# Long-Term Vision

The app should evolve into:
- a personal heritage navigator
- a lineage archaeology tool
- a semantic exploration environment
- a continuity map
- and a work surface for thought.

The graph is not:
- a report
- a dashboard
- or a backlink visualization.

It is:
- a navigable cognitive environment
- a semantic topology
- and an inhabitable landscape of continuity.
