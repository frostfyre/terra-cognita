# AppFocus / Graph Workbench

A native macOS app that treats a heritage graph (a markdown vault of people,
events, institutions, works, and concepts) as the primary work surface —
navigable, queryable, inspectable, and semantically meaningful.

See [`Design/DESIGN.md`](Design/DESIGN.md) for the full design document.

---

## Status

Early prototype. Builds and runs as a Swift Package Manager macOS executable.

**What works today**

- Loads an Obsidian-style markdown vault from `Data/heritage-vault/heritage-vault/`,
  parsing YAML front-matter as node attributes and `[[wikilinks]]` (plus
  Dataview-style `key:: [[target]]` inline relations) as typed edges.
- Renders the entire graph (~300 nodes / ~1000 edges) in a single SwiftUI
  `Canvas` for high frame-rate pan / zoom.
- Force-directed layout (Fruchterman–Reingold variant tuned to feel like
  Force Atlas 2) computed on a background `Task` and crossfaded in over a
  circular seed.
- Subtle ambient drift via `TimelineView` so the canvas feels alive.
- Selection + 2-hop BFS neighborhood highlight: clicking a node dims
  everything outside its 2-hop subnet.
- Scroll-wheel zoom and middle-mouse drag pan via window-scoped `NSEvent`
  monitors layered behind the SwiftUI canvas (so left-click selection still
  works).
- Right-click context menu with **Open note** (launches the backing
  markdown file in the default app).

**Known gaps**

- Layout is computed once on load; no live re-simulation, pinning, or
  manual drag-to-position yet.
- No side-panel `NodeInspectorView` wired up (markdown body, metadata,
  inbound / outbound links).
- macOS-only at present (SwiftPM executable target). iOS will require an
  Xcode app project wrapper.
- No edge-provenance editing, lenses, surface modes, Apple Intelligence
  integration, or 3D mode yet — see DESIGN.md.

---

## Build & Run

```bash
cd AppFocus
swift run AppFocus
```

The app launches in foreground mode (`NSApplication.setActivationPolicy(.regular)`
is called in `AppFocusApp.init()` because `swift run` produces a bare binary
with no `Info.plist`).

Requirements: macOS 14+, Swift 6 toolchain, Xcode 16+.

---

## Project Structure

```
AppFocus/
├── Package.swift                 — SwiftPM manifest (executable target)
├── Sources/AppFocus/
│   ├── AppFocusApp.swift         — @main App
│   ├── GraphView.swift           — Top-level view; kicks off vault load
│   ├── GraphCanvasView.swift     — Canvas-based renderer + gestures
│   ├── GraphStore.swift          — @MainActor ObservableObject for graph state
│   ├── VaultLoader.swift         — Markdown vault → Graph (front-matter + wikilinks)
│   ├── ForceDirectedLayout.swift — Background force-directed solver
│   ├── GEXFParser.swift          — GEXF import path (Foundation XMLParser)
│   ├── HeritageGraph.swift       — Mutable node/edge container
│   ├── Node.swift / Edge.swift / Provenance.swift — Domain types
│   ├── NodeInspectorView.swift   — (designed, not wired) markdown + metadata panel
│   └── …
├── Data/heritage-vault/          — The markdown vault (the actual content)
├── Design/DESIGN.md              — Full design / vision document
└── Tests/app_focusTests/         — Test stubs
```

---

## Interaction

| Action                     | Input                          |
|----------------------------|--------------------------------|
| Pan                        | Middle-mouse drag              |
| Zoom                       | Scroll wheel · pinch (trackpad)|
| Select node                | Left click                     |
| Clear selection            | Right-click → Clear selection  |
| Open backing markdown file | Right-click → Open note        |

Selecting a node dims everything outside its 2-hop neighborhood so the
focused subnet stands out.

---

## Roadmap

Loosely following DESIGN.md, in approximate order:

1. **Node Inspector side panel** — markdown body, metadata, inbound /
   outbound links, edge explanations.
2. **Lens system** — saved semantic views (Artistic Lineage, Seamwalkers,
   Technical Art Lineage, etc.).
3. **Edge provenance editing** — DESIGN.md's seven categories of
   relationship (direct influence, verified lineage, institutional
   connection, inferred affinity, recommendation, adjacency, speculation).
4. **Surface modes** — Explicit Graph, Focused Semantic, Temporal,
   Systems, Reflective.
5. **Apple Intelligence integration** (FoundationModels) — natural-language
   graph queries, summarization, edge suggestion with provenance.
6. **3D mode** — time as depth axis, SceneKit or RealityKit.
7. **Proper iOS / macOS Xcode app targets** for shipping.
