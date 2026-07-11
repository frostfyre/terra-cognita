# macOS 1.0 — App Store listing draft (for review)

App record: **Terra Cognita Atlas** (shared with iOS via Universal Purchase — name,
IAP, and privacy answers carry over; the macOS *platform version* needs its own
description, keywords, screenshots, and What's New).

## Name (app-level, already set)
Terra Cognita Atlas

## Subtitle (30 chars max)
Graph-first knowledge atlas
*(27 chars)*

## Category
Productivity (match iOS)

## Price
Free · In-App Purchase: **Pro Renderer** — $4.99 non-consumable
(`com.frostfyre.terracognitaatlas.pro`, Universal Purchase: buy once, unlocked on
iPhone, iPad, and Mac)

## Promotional text (170 chars max)
Now on Mac. Your atlas is plain Markdown in a folder you choose — no accounts, no
telemetry, AI on-device. One purchase unlocks Pro on iPhone, iPad, and Mac.

## Description (4000 chars max)

Most tools visualize graphs. Terra Cognita thinks in them.

Terra Cognita Atlas is a graph-first semantic explorer for the ideas, people,
events, and works that make up your knowledge. The graph isn't a diagram bolted
on for show — it's the territory you navigate. Nodes mark the stops; the
structure lives in what connects them.

BUILT FOR THE MAC
A native macOS app with full keyboard, mouse, and trackpad support. Pan and zoom
a living force-directed field, hover to probe connections, and work your atlas
in a real window alongside your other tools.

THINK IN TERRITORIES
• Five layout algorithms — force-directed, circular, radial, hierarchical, and
  grid — with smooth transitions that preserve your spatial memory.
• Lenses filter the field by type, so one atlas can be read as a family tree, a
  concept map, or a timeline of works.
• Hop highlighting dims everything beyond N connections from your selection, so
  neighborhoods pop out of dense fields.
• Node size encodes connectivity — hubs read bigger than leaves at a glance.

YOUR FILES, YOUR TERRITORY
Your atlas is a folder of plain Markdown files on your Mac, in a location you
choose. Open the notes in any editor. Move them. Back them up. Sync them however
you like. Terra Cognita never sees them — there are no accounts, no cloud, no
telemetry, no analytics. AI-assisted capture runs entirely on-device through
Apple's Foundation Models (requires macOS 26).

BRING YOUR OWN GRAPHS
Import GEXF graph files or point Terra Cognita at an existing Markdown folder
with wikilinks. A bundled concept atlas ships with the app, so there's territory
to explore the moment it launches.

PRO RENDERER (OPTIONAL)
A one-time $4.99 purchase unlocks a Metal-powered renderer with an
order-of-magnitude speedup on large atlases — tens of thousands of nodes, fluid.
The free app is never limited in what it can hold or open: Pro speeds up the
view, it never gates your data. One purchase covers iPhone, iPad, and Mac.

Terra Cognita stores nothing outside the folder you choose and transmits nothing
you didn't explicitly ask it to fetch.

*(~2,150 chars — room to grow if you want feature call-outs added)*

## Keywords (100 chars max)
`knowledge graph,mind map,markdown,notes,zettelkasten,pkm,concept map,graph viewer,gexf,second brain`
*(99 chars — "atlas" omitted since it's already in the app name; competitor app
names deliberately avoided to dodge a metadata rejection)*

## What's New (1.0)
Initial release on the Mac. Explore Markdown atlases as living graphs: five
layouts, type lenses, hop highlighting, GEXF import, on-device AI capture, and
an optional Metal Pro renderer for very large graphs.

## Screenshots — capture plan (needs a manual pass)
Mac App Store accepts 16:10 at 2560×1600 or 2880×1800 (1–10 images). Suggest
recreating the three iPad compositions at 2880×1800 with the bundled Miyazaki
atlas in a tidy window:
1. Hero: full field, force-directed, a hub selected with gold ring + hop dimming.
2. Lens view: lens picker open, field filtered by type.
3. Layout menu open mid-transition (or radial layout from a selection).
Capture: `Cmd+Shift+4 + Space` on a 2880×1800-capable display, or window capture
and pad to 16:10 on the navy background.

## App Review notes (paste into the Review Information box)
- The app ships with a bundled sample atlas; no account or setup is needed.
- The only IAP is a non-consumable "Pro Renderer" ($4.99) reachable via the PRO
  badge in the toolbar. It only switches the rendering engine; all content
  features are free.
- The app reads/writes only user-selected folders (sandboxed,
  user-selected-files entitlement). Microphone is used for on-device dictation
  capture only.
- No login, no server component, no data collection.

## Also confirm in ASC before submitting
- macOS platform version 1.0 exists on the shared app record with build
  **2607091604** attached once processing finishes (10–30 min after upload).
- Privacy nutrition label: carries over app-level from iOS ("Data Not
  Collected") — verify it shows for macOS too.
- Territories/pricing inherit from the app record (all territories, free).
- Export compliance: standard encryption exemption (HTTPS only) — same answer
  as iOS.
