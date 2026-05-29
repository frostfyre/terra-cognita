# Atlas Genesis

The conversational atlas-creation flow that ships inside
`TemplatePickerSheet`. The user describes the atlas; the AI extracts
a starter constellation; the user shapes it before the atlas is
born. Built in phases — A is shipped, B/C/D/E are the remaining
push toward "gold-standard density" (heritage atlas / Miyazaki demo
quality from a chat session).

The on-device model is small. The whole point of the multi-phase
plan is that *iterative deepening + targeted enrichment* compensates
for what a single AI turn can't deliver.

---

## Phase A — Chat-driven first turn *(landed)*

Lives in `Sources/TerraCognitaKit/AtlasGenesisChat.swift`.

- Free-form input + mic dictation + Send button
- Single-turn `runCapture(text:graph:)` against an *empty* graph
  (we're building a new atlas; existing-labels from the loaded one
  would pollute the proposals)
- Constellation preview with per-node accept/reject toggles
  (header counter reads "accepted / total")
- Status banner for `Foundation Models unavailable` so the user
  doesn't tap Send into the void
- `.submitScope()` keeps the keyboard's Return inside the chat so
  it can't fire the sheet's Continue toolbar action
- Auto-create at `~/Documents/Terra Cognita Atlases/<Template> Atlas/`
  (with ISO timestamp suffix on name collision) so the user never
  fights a folder picker after they've done the real work
- "Empty constellation → fall through to the classic folder-picker
  flow" remains as the no-AI escape hatch

Status: green on macOS; iOS sheet flow is fragile but the genesis
path now skips the second sheet entirely.

---

## Phase B — Persistent session, multi-turn refinement *(next)*

Goal: each subsequent message in the chat *extends* the existing
constellation rather than replacing it. The chat should feel
genuinely conversational ("go deeper on Studio Ghibli", "what's
missing from the post-war period?", "drop X, keep Y").

### Architecture changes

- New `runGenesisTurn(text:current:)` on `NodeIntelligence` that
  keeps a `LanguageModelSession` alive between turns. First turn
  creates the session; subsequent turns reuse it.
- The session's transcript carries context implicitly — we no
  longer need the hand-built `composedPrompt(latest:)` string-
  smashing helper.
- New `@Generable` schema `GenGenesisTurn` that returns *deltas*:
  `nodesToAdd`, `nodeIDsToRemove`, `bodyPatchesForLabel`, plus a
  short prose `summary` for the chat bubble.
- `AtlasGenesisChat.runTurn` applies the deltas to the working
  constellation in place; the preview re-renders.

### UX touches

- New nodes briefly glow gold on insertion so the user can see what
  changed.
- A tiny "↺ Reset session" affordance to wipe context if the
  conversation goes sideways.
- Token-budget watch: if the session hits `exceededContextWindowSize`,
  start a fresh session pre-seeded with the current constellation
  as system context.

### What it doesn't fix

- Breadth-in-one-shot ceiling. A single turn still won't enumerate
  every Marvel character. Phase C is what gets us there.

---

## Phase C — Per-node deep expansion *(tomorrow)*

The single most impactful phase for atlas density. After Phase B,
the user can grow the constellation conversationally; Phase C lets
them grow it *recursively from any node*.

### Decisions

- **Trigger:** inline `arrow.triangle.branch` icon on each row in
  the constellation preview. Tap → opens deepen sheet for that node.
  (Long-press menu is more discoverable on macOS but worse on iPhone;
  inline icon wins for parity.)
- **Child cap:** 8 per deepen call. Matches existing structured-op
  caps; higher values dilute quality on the on-device model.
- **Indentation:** track `parentLabel: String?` on `Constellation.NewNode`
  so the preview can indent and prefix `↳`. Lets the user see what
  came from where.
- **UX:** dedicated sheet with the proposed refined body editable
  + a list of proposed children (each individually accept/reject).
  Commit → applies to working constellation.

### Architecture

- New `NodeIntelligence.runDeepen(node:context:)` method.
- New schema:

  ```swift
  @Generable
  struct GenDeepenedNode {
      @Guide(...) var refinedBody: String
      @Guide(.count(0...8)) var children: [GenCaptureNode]
  }
  ```

- New `Constellation.NewNode.parentLabel: String?` for hierarchy.
- New `AtlasGenesisDeepenSheet.swift` view.
- `AtlasGenesisChat.constellationPreview` row gets the deepen icon
  + the indent + child-count badge ("2 ↓").

### Prompt shape

```
You are deepening atlas node "<X>" of type <T>.
Current body:
"""
<body>
"""
Other nodes in the constellation (don't duplicate, may cross-link):
- A [person]
- B [work]
- ...

Propose:
(1) `refinedBody` — 3–5 paragraphs synthesizing why <X> matters to
the heritage, in the author's voice. Preserve every existing
[[wikilink]] verbatim.
(2) `children` — up to 8 related nodes that should join the atlas
around <X>: people who shaped it, works that defined it, concepts
it embodies, events that resolved it. Each child gets a substantive
body, type, optional era, and `linksToExisting` against the
constellation labels above.
```

### Density model

Each turn adds 5–8 substantive nodes. After 3–4 deepening rounds
on different topics, you're at 30–50 nodes — close to heritage-
atlas density.

---

## Phase D — Wikipedia enrichment per accepted node

Already half-built via `WebEnrichment` + the existing Capture flow.
Genesis just needs to call it.

- After Phase C commits a deepen, fire `WebEnrichment.summary(for:)`
  in the background for each new node (already has opensearch fuzzy
  fallback as of `1a0082b`).
- Fold the extract into the body with a `*From Wikipedia:* …`
  demarcation, mirroring how `CaptureSheet` did it.
- Badge enriched nodes with a small globe in the preview.

Background-fired, non-blocking. If Wikipedia is offline or there's
no match, the node keeps its AI-drafted body.

---

## Phase E — Anchored seed prompts + streaming + polish

- **Mode-specific seed prompts.** Picking "Heritage Atlas" template
  pre-primes the genesis session with style guidance: "Draft each
  node with the depth + cross-referencing of a curated heritage
  atlas — see the Miyazaki demo for shape." Career Map gets its own
  prompt. Story Bible gets another. The template's `seedPrompt`
  field carries this.
- **Streaming response.** Use FoundationModels' streaming API so
  the constellation grows in front of the user during the first
  turn instead of appearing after a multi-second delay.
- **"Regenerate this node"** affordance — second-tap of the deepen
  icon. Useful if the first proposal misses.
- **Undo within the chat session** — every turn pushes a snapshot
  onto a stack; `⌘Z` rewinds.
- **Reasonable error recovery** — refusal → "I can't help with
  that"; timeout → retry button; partial response → keep what we
  got.

---

## What we know works *(today's bar)*

After Phase A, the chat can take a paragraph like:

> "An atlas about the Coen Brothers — their films, recurring
> collaborators, themes, and the cultural moments that shaped each
> period of their work."

…and produce ~8 starter nodes that commit cleanly into a fresh
atlas at `~/Documents/Terra Cognita Atlases/Continuity Atlas/`.

After Phase C, the same starter could be deepened into 30–50 nodes
across 3-4 rounds of recursive expansion.

After Phase D, every accepted node carries a Wikipedia extract
where applicable.

After Phase E, the experience feels like the real working session
the user had with Claude and ChatGPT to build the heritage atlas
in the first place — except inside the app, on-device, owned by
the user.

---

## Open calls before Phase C

1. Where does the deepen sheet live structurally — inside the
   genesis chat (modal-over-modal on iOS, fine on macOS) or pushed
   onto a NavigationStack inside the template picker? Lean: modal
   sheet, identical pattern everywhere.
2. When the user deepens a node that's a child of another deepened
   node, do we let the chain go indefinitely or cap at depth 3?
   Lean: uncapped — depth is the whole point.
3. Edge taxonomy of child relationships — do we let the AI propose
   `relationshipType` per child link (e.g., `created`, `influenced-by`),
   or leave them as bare wikilinks for v1? Lean: bare for v1, types
   in Phase E polish.
