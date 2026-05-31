# Terra Cognita: Audio Design

## Intent

Audio in Terra Cognita is an **identity layer**, not decoration. The product's visual register is already poetic — constellation field, glowing nodes, atmospheric bloom — and inherently invites a sonic counterpart. Done right, audio elevates Terra Cognita from "tool" to "environment."

The audio design is bound to the product thesis: **structure is in the connections**. The signature audio feature (chime sonification) makes the connections *audible*. The graph becomes something you can listen to, not just look at.

## Three Audio Layers

Three functionally distinct layers, each doing different work:

| Layer | Role | Source | Priority |
|---|---|---|---|
| Chime Sonification | Information | System-generated from graph topology | Identity (highest) |
| Per-Atlas Music Binding | Mood | User's local Apple Music / iTunes library | Personalization |
| Ambient Bed | Atmosphere | Generative or curated loops | Polish (lowest) |

These coexist via mixing/ducking — they are not alternatives.

---

## Layer 1: Chime Sonification (Identity)

### Concept

On node selection, a chime arrangement plays whose properties summarize the node's connections. Pitch, timbre, spatial placement, and sequence are all derived from the node's role in the graph. The chord blooms and decays over roughly 1–3 seconds.

The user is hearing the node's place in the topology. Power users will learn node *signatures*: hubs sound like cascades, leaves like single notes, bridges between dense clusters have characteristic intervals. Without ever counting edges, a user comes to know "this is a hub" or "this is isolated" by ear.

This is the identity piece. It is the strongest differentiator and should be implemented first within v1.1.

### Trigger

- Primary: node tap / selection
- Possible secondary (future): edge-traversal animation, search result reveal

### Mapping Rules

One chime per connected node. Each chime's properties derive semantically from the connection:

- **Pitch** — from the connected node's type or color. People in one register, films in another, concepts in a third. The graph's color palette becomes a harmonic palette.
- **Sequence order** — chimes ring in the spatial order of connected nodes on screen (e.g., clockwise from top, or arc-sweep). Audio sweeps the same arc the eye does.
- **Timbre** — from edge type. "Influenced by" / "directed by" / "appears in" each carry distinct sonic character (e.g., bell vs. prepared piano vs. struck glass).
- **Spatial placement** — each chime placed in the stereo field at the actual on-screen position of its connected node. With AirPods spatial audio, the user literally hears *where* the structure is. This is the killer feature.

### Density Management

High-degree nodes (e.g., Studio Ghibli, with dozens of edges) cannot ring all chimes simultaneously without becoming noise.

Strategy: **bloom, not slam.**

- Stagger chimes across ~1–3 seconds with overlapping decay
- Tempo scales with degree (denser nodes ring faster)
- Suggested soft cap: first ~20 chimes audible + faint sustained pad representing the rest (tune by audition)

### Scale & Instrumentation

- **Scale family**: pentatonic or diatonic. Forgiving — almost any combination sounds pleasant. Chromatic risks chaos. Pick before audition work or you'll be debugging dissonance forever.
- **Instrument character**: sampled instruments with overtones, body, and air. NOT generic synth tones. They should sound *played*, not synthesized.

#### Reference Territory

- Instruments: singing bowls, glass armonica, struck crystal, prepared piano harmonics
- Artists for tonal register: Hiroshi Yoshimura, Volker Bertelmann (Hauschka), Brian Eno (*Apollo* register)

### Open Questions

- Specific scale choice (e.g., E minor pentatonic? Lydian mode?)
- Custom-recorded vs. licensed sample library
- Decay duration and overlap parameters
- Exact threshold and behavior of the soft cap on high-degree nodes
- If edges carry weight, how it modulates pitch/duration/loudness

---

## Layer 2: Per-Atlas Music Binding (Personalization)

### Concept

Users associate music (track, album, or playlist) with each Atlas. Opening the Atlas auto-resumes the music. **The binding is the feature** — playing music in the background is something every app enables passively. What's distinctive here is that each Atlas *remembers* its pairing.

Example: open Miyazaki Atlas → Joe Hisaishi resumes. Switch to a philosophy Atlas → Tangerine Dream takes over. Each domain has its sonic identity.

### Mechanism

1. User selects music via in-app picker (track, album, or playlist)
2. Selection persisted as Atlas metadata
3. Auto-resume on Atlas open (with clear user-facing pause/override)
4. Music continues across node selections — does not pause for chimes (see Composition & Mixing)

### Implementation

- **API**: MusicKit on Apple platforms
- **Library scope**: Apple Music subscription content + iTunes-purchased + iCloud Music Library + on-device library
- **Storage**: persist music identifier(s) as Atlas metadata (track/album/playlist ID + service identifier)
- **Authorization**: request MusicKit authorization on first music-binding action, not at app launch

### Caveats

MusicKit only reaches Apple's music ecosystem. Spotify / Tidal / YouTube Music users can still play those services externally before opening Terra Cognita, but the per-Atlas binding will not work for them. This is a real cohort within the already Apple-only audience.

### Open Questions

- Playlist randomization vs. always saved order?
- Behavior on Atlas close — pause, continue, or fade?
- Handling music that's no longer available (deleted from library, removed from Apple Music catalogue)?
- Should the picker present time-shaped options ("music for 30 min" vs. "loop album")?

---

## Layer 3: Ambient Bed (Atmosphere)

### Concept

Optional, subtle generative or looped ambient sound that sits underneath both other layers. Provides atmospheric ground without competing for attention.

**Lowest priority of the three.** Decoration, not differentiation. Easy to do poorly — becomes noise after 20 minutes. Needs strong taste discipline. Ship last, or skip until clearly wanted.

### Reference Territory

- Hammock
- Stars of the Lid
- Brian Eno, *Apollo: Atmospheres and Soundtracks*
- GAS (Wolfgang Voigt)

Thin, spacious, slightly mystical. Generous with silence. NOT synthwave, NOT chillhop, NOT anything with a beat.

### Open Questions

- Generative or fixed loops?
- Single ambient layer for the whole app, or per-Atlas variants?
- If commissioned, who composes? (External collaborator likely needed.)

---

## Composition & Mixing

### Layer Coexistence

All three layers may play simultaneously. They occupy distinct frequency and functional roles:

- **Music**: typically broadband, can dominate without ducking
- **Chimes**: transient, high-mid frequencies, sharply defined
- **Ambient bed**: low-mid pad, very low presence

### Ducking Logic

When chimes trigger:

- Music ducks by ~6–9 dB for the chime duration + short tail (~250–500 ms release). Suggested starting point; tune by ear.
- Ambient bed ducks slightly less (~3–4 dB)
- Chimes themselves play at the user's chosen mix level

Ducking should be perceptually smooth — sidechain-style on the music bus, not a hard gate.

### Volume Controls

Independent volume per layer in settings:

- Music
- Chimes (sensible default: ~60% of music level when both active)
- Ambient bed

Plus a single master "audio enabled" toggle for users who want silence by default.

---

## Defaults & Discovery

### Recommended defaults

- All three layers default OFF on first launch
- Sound icon visible in the main UI, clearly toggleable
- Respect system mute switch / silent mode on mobile

### Discovery moment

The first chime arrangement a user hears must land memorably. When audio is first enabled, consider opening the Miyazaki vault as a demonstration — a known graph with known interesting structure, calibrated to show off the sonification.

The first 5–10 seconds after audio is enabled will disproportionately shape whether the user keeps it on. Treat them as a designed moment.

---

## Sequencing & Scope

### V1 (current launch target)

**No audio is in scope for v1.** Packaging and core feature work take priority. Ship silent.

### V1.1 (post-launch)

Priority order:

1. **Chime sonification** — identity piece. Ship first.
2. **Per-Atlas music binding** — personalization. Ships second.
3. **Ambient bed** — polish. Last or skip.

Rationale: the chime feature defines what Terra Cognita *feels* like in a way no other tool offers. Music binding is enjoyable but additive. The ambient bed risks becoming noise without careful taste discipline.

---

## Naming

Working placeholders for the chime feature:

- Thought Chime
- Sonic Space

The final name should emerge from living with the implemented feature. Naming is not a blocker for implementation.

---

## Strategic Notes

- Sonification of graph topology is **defensible product territory**. Novel enough to be written about and imitated, but the careful design (pitch mapping, instrument choice, spatial placement) is hard to clone superficially.
- Even if most users keep audio muted on mobile (which most will, on phones), the feature has outsized value for **demos, landing-page video, App Store preview, and word-of-mouth**. The audio quality of the first 30 seconds someone sees of Terra Cognita disproportionately shapes their impression of the whole product.
- The chime feature is content unto itself. A short demo video with audio on ("here's what tapping a node sounds like") is a strong reveal post for the v1.1 launch.

---

## Out of Scope

Explicitly NOT part of this audio identity vision (may be considered later, but not currently):

- Voice control, voice commands, or any speech-related audio input
- TTS / audio reading of node notes
- Music creation or composition tools within Terra Cognita
- Audio recording / voice memo capture
- Streaming service integrations beyond Apple's MusicKit (no Spotify SDK, no Tidal, no YouTube Music)

These may be considered separately, but they are NOT part of the three-layer audio design described above.
