# Paul's Heritage Map

A graph network of artistic, creative, and professional heritage — passive influences, limited encounters, sustained relationships, family and personal figures across literature, comics, painting, games, tech art, music, and methodological formation.

Built collaboratively in conversation. Intended to live in Obsidian as the writing surface, with periodic GEXF export for Gephi analysis.

## Design philosophy: build the whole map, filter for use

**The data layer is honest and complete; the views are opinionated and selective.** The map captures the truth of how Paul became who he is — including personal, family, and friend figures alongside professional and aesthetic ones. Specific *uses* of the map (LinkedIn promotion, negotiation prep, creative-development analysis, family archive) are filtered views over the same underlying graph, not separate artifacts.

This means:

- The vault can include sensitive or personal entries without pulling its punches.
- The same node can be useful for different purposes at different filter settings.
- Selectivity happens at the *application* layer, not at the *capture* layer.

## Structure

Folders by node type:
- `people/` — individuals (creators, mentors, peers, friends, family, encountered figures)
- `works/` — specific books, comics, games, films, paintings that warrant their own node
- `events/` — discrete moments (the Spectrum road trip, the Usenet job posting, the Bisley lecture)
- `institutions/` — studios, schools, conventions, traditions
- `concepts/` — function-tags and methodological lineages substantial enough to be nodes themselves

## Node schema

Each node has YAML frontmatter:

```yaml
type: person | work | event | institution | concept
tier: passive | limited | sustained | self
medium: [literature, comics, painting, film, games, tech-art, music, religion-philosophy, animation, etc.]
primary_medium: visual-artist | writer | musician | animator | game-developer | educator | other
era: [pre-conscious, self-choosing-childhood, bridge, early-career, blizzard-era, post-blizzard, current]
peak-era: single era value — when the node was most central to Paul's life
function: [open list of function-tags]
sensitivity: public | professional | personal
dates: optional date or range
status: stub | drafted | rich
```

`primary_medium` guidance:
- Single value for clean filtering in Gephi (color-code or filter by this field)
- Use `medium` for the full multi-value range; use `primary_medium` for the dominant category
- **visual-artist**: painters, illustrators, draughtsmen, comics artists whose primary output is images (Moebius, Horley, Wendling, Frazetta, Toppi, Brom, Gurney, McGinnis, etc.)
- **writer**: authors whose primary output is prose or script, including comics writers who are primarily literary (Gaiman, Le Guin, De Lint, Pratchett, Moorcock, Tolkien, Herbert, Heinlein, Twain, Rothfuss, etc.)
- **musician**: performers and composers (Tori Amos, Björk, Metric, Taylor Swift, Joan Jett, Heart, Metallica, etc.)
- **animator**: figures whose primary medium is animated film or sequential narrative (Miyazaki, Chuck Jones, Jeff Smith — writer-who-draws; Walt Kelly — same)
- **game-developer**: industry colleagues whose primary output is games (Scharmen, Aguilar, Adams, Hall, Cortez, Kennedy, etc.)
- **educator**: figures whose primary map function is teaching (Vilppu, Gula — though many also carry visual-artist)
- **Difficult cases**: The Pinis → `visual-artist` (Wendy's hand is primary); Jeff Smith → `animator` (writer-who-draws tradition); Gaiman → `writer` (literary register primary despite comics medium)
- New nodes should include `primary_medium`; retroactive audit is a future pass

`peak-era` guidance:
- Use the single era where a figure or work was *most central*, even if they span multiple eras
- Tori Amos example: `era: [bridge, ongoing]` but `peak-era: bridge` (when the live-show pilgrimage was most intense)
- Blizzard Entertainment example: `era: [blizzard-era]` and `peak-era: blizzard-era` (single-chapter)
- Retroactively adding peak-era is a future audit pass; new nodes should include it
- In Gephi: use peak-era as the color-coding attribute for temporal visualization
- For full dynamic/temporal graph capability, tag nodes and edges with date ranges in GEXF and use Gephi's timeline filter — more setup work, worth doing if temporal views are actively used

`tier` definitions:
- **passive** — studied or absorbed closely but never met
- **limited** — direct exposure ranging from a day to a week
- **sustained** — weeks to years of direct contact
- **self** — events / chapters of Paul's own life

`sensitivity` definitions:
- **public** — fine to surface in any context (published creators, public figures, well-known institutions)
- **professional** — fine in industry / colleague contexts but not for casual public promotion (named industry colleagues who haven't chosen public visibility)
- **personal** — private use only; family, romantic partners, friends not in the public eye, sensitive personal events

For non-public living people, default to first-name-or-relationship-only unless they've chosen public visibility through their work. The map can hold them with appropriate weight without making them casually identifiable beyond Paul's intent.

## Edge conventions

Connections are wikilinks `[[Like This]]` in the prose body. Optionally tag the relationship type inline using the conventions:

- `influenced-by:: [[Node]]`
- `colleague-of:: [[Node]]`
- `introduced-by:: [[Node]]`
- `mentored-by:: [[Node]]`
- `encountered-at:: [[Node]]`
- `rhymes-with:: [[Node]]` (structural / functional resonance, not direct influence)
- `counterweight-to:: [[Node]]`

## Function-tag vocabulary (open, growing)

Working set from current conversation:

- `worldbuilding-mode-mythopoeic` — Tolkien-shaped, deep-time invented history
- `worldbuilding-mode-recursive-multiverse` — Moorcock-shaped, parametric instances of an archetype
- `worldbuilding-mode-competence-as-realism` — Heinlein-shaped, mechanism-as-worldbuilding
- `worldbuilding-mode-interlocking-systems` — Herbert-shaped, ecology-religion-economics coupled
- `visual-author-loyalty` — loyalty to a hand, not a property (Wendy Pini, Moebius)
- `operatic-tragic-register` — Elric, Dark Phoenix, doomed-protagonist-as-problem
- `comic-fantasy-register` — Pratchett, Asprin, Foglio
- `methodological-purist-anchor` — classical-PBR, simulation rigor, examinability
- `comparative-pluralist-method` — multiple-coherent-frameworks, no absolute truth
- `role-authoring` — the lifelong pattern of writing one's own job description
- `peer-credentialed-rather-than-consumer-credentialed` — visible to the field, not the public
- `network-mover` — people who put your name into rooms you weren't in
- `network-mover-bidirectional` — relationships durable enough that *either party* brings the other across studio transitions
- `curator-of-institutional-art-education` — the Cranford function; designs the rooms and rosters Paul ends up in
- `deliberately-chosen-mentor-figure` — figures Paul actively oriented toward in order to learn from them (the Joey Ray Hall function)
- `retroactively-discovered-upstream-influence` — figures whose curatorial or creative work shaped Paul's earlier formation, only recognized as such after a later relationship formed
- `fully-present-participant` — the disposition of treating an institutional resource as if it were yours to extract maximum value from, even when someone else is running it (the academy attendance, the Spectrum pilgrimage, life drawing maintained as a tech artist). The opposite of inflating role descriptions — the *show up to the thing, all the way* disposition.
- `accurately-seen-by-senior-figure` — the Barnard function
- `music-as-worldbuilding-substrate` — the De Lint / O'Malley method; specific named music as load-bearing diegetic texture
- `performance-author-loyalty` — following an artist's live work across decades and venue scales (Tori Amos, Metric, Björk)
- `adult-aesthetic-landing` — fifth tier; works absorbed under already-developed taste, diagnostic of current sensibility rather than formative
- `female-fronted-authorial-project` — confirmed cluster on the music axis; through-line refined to *interior-or-formal register under uncompromising authorial vision*
- `public-exemplar-of-stances-held-privately` — figures Paul respects for their visible enactment of stances he holds privately (Taylor Swift, Björk, Joan Jett; probably Brom)
- `bar-setter-acknowledged-as-unreachable-but-admired` — figures whose excellences are not Paul's but whose standards calibrate his sense of what craft-in-general looks like (Yngwie's virtuosity; probably retroactively Donato, Gurney, Wei Wang, Moebius in their respective domains)
- `eternal-student` — top-tier dispositional anchor; Paul's *constantly forming* register; makes the [[fully-present-participant]] disposition self-renewing
- `assume-I-know-nothing` — top-tier dispositional anchor; the epistemic stance that makes [[eternal-student]] possible; keeping the investigation open by holding non-knowledge as default starting position
- `seam-walking` — meta-concept; the underlying disposition that runs across cognitive, methodological, and somatic registers; Paul is consistently drawn to places where two domains meet
- `opportunity-orientation` — how Paul moves toward seams; the strategic counterweight to the patient dispositions that prevents them from collapsing into passivity
- `cross-disciplinary-translation-with-trap-awareness` — how Paul operates when at a seam; the disposition of moving through adjacent disciplines while staying alert to where the apparent analogies break
- `frisson-between-extremes` — what Paul's body recognizes as home; the somatic / aesthetic register of the seam-walking disposition (beaches, mountaintops, mountain streams, Sedona)
- `forward-investment-self-directed-study` — the disposition of building expertise on speculation, before there's a professional context that demands it (the Renderman / BMRT / SIGGRAPH self-study layer; an [[eternal-student]] sibling, not a sub-tag)
- `dual-training-convergence` — the structural claim that Paul's current sim2real position emerges from convergence of [[Blizzard Entertainment|Blizzard]]-visual-craft-formation and [[Amazon Game Studios|Amazon]]-software-and-ML-formation, **on top of** the [[autodidact-foundational-stream]] prerequisite layer
- `autodidact-foundational-stream` — the self-directed training layer (SIGGRAPH / Renderman / BMRT / SGI era) that established the *understand-the-mechanism-underneath* disposition before either studio chapter; foundational rather than parallel
- `cross-stakeholder-legibility-as-primary-value` — building technical work that legibly serves multiple professional traditions simultaneously; the disposition Paul cited as *more important than* the underlying ML achievement of the 9-language lipsync pipeline
- `organizational-craft-as-legitimate-work` — treating relational-organizational work (politics-reading, trust-building, cross-team navigation) as legitimate craft equally weighted with technical work, rather than as overhead. The intra-organizational expression of the [[high-trust-relationship-architecture]] disposition.
- `BMRT-recognition-token-peer` — peer relationships formed through shared autodidact-foundational-stream backgrounds; specialized formation as recognition signal between practitioners
- `shared-formation-produces-recognition` — broader version of the above; any shared formation layer (Vilppu + Jones with Scharmen, BMRT with Rudy Cortez) that creates working vocabulary between collaborators without needing negotiation
- `convergent-formation-discovered-retroactively` — two people independently drawn to the same influence, who discover the convergence later; more remarkable than shared formation (the Chandra/Elfquest instance)
- `encounter-that-shifted-mental-model-without-relationship` — discrete encounters that change what Paul conceives possible at scale, without producing a sustained relationship (the [[BioWare interview]] is the prototype)
- `direct-instructor` — actually taught Paul, in person, in a classroom or studio session
- `still-followed-via-published-work` — active relationship to a tradition via someone's ongoing publishing, beyond the formal teaching window
- `low-maintenance-connection` — relationship in good standing where trajectory divergence explains sparse contact; distinct from low-bandwidth-sustained-contact (which is actively maintained lightly) and understood-distance (which is calibrated by the other party's circumstances). The connection would activate more if contexts aligned; the current path divergence is the explanation, not a diminishment.
- `understood-distance` — real relationship with low active-contact probability for understandable reasons (e.g. Pierina Merino — 100% committed to company, wouldn't expect contact unless business need)
- `active-backing` — actively looking for ways to support someone's work because the work deserves support; not transactional, not career-adjacent (e.g. Amir Satvat)

This vocabulary is meant to grow. Add tags as patterns reveal themselves.

## Open threads (not yet built into nodes)

- ~~The cohort that came into Blizzard with John Scharmen~~ → **Resolved**: Scharmen + [[Steve Aguilar]] only. The rest of the [[Sony San Diego animation team]] stays Sony-era.
- Other Spectrum encounters across the years (only the named-trip set is captured)
- ~~Library/academy instructors~~ → **Resolved (named)**: [[Tim Gula]], [[Steve Huston]], [[James Gurney]], [[Nathan Fowkes]], [[Bob Watts]]; **curator [[Jeremy Cranford]]** also placed. Specific curricula, master-study traditions, and library art books still open.
- SIGGRAPH-window technical figures (Museth, Stam, Bridson, the Houdini lineage, production-paper authors)
- The post-bridge "settled adult reader" period — what filled the literature shelf after the bridge cohort
- ~~Film, television, music, fine art outside fantasy-painter axis~~ → **Music substantially developed**: [[female-fronted-authorial-project]] is a forty-five-year continuous cluster with bedrock trio ([[Joan Jett]], [[Heart]], [[Pat Benatar]]), bridge / lifelong tier ([[Tori Amos]], [[Björk]] from Sugarcubes era), adult-aesthetic-landing ([[Metric]] via [[Scott Pilgrim]], [[Taylor Swift]]), pattern-fit-but-lower-weight ([[PJ Harvey]], [[Fiona Apple]]). Plus [[Metallica]] as heavy-register formative anchor and [[Yngwie Malmsteen]] as virtuosity-bar-setter. Music beyond these still open. Film, TV, fine art outside fantasy-painter axis still open.
- **Lineage expansion** — in progress. Tier 1 (high-confidence) nodes written: [[Howard Pyle and the Brandywine school]], [[Frank Reilly method]], [[Alfred Kroeber]], [[John Blanche]], [[Mervyn Peake]], [[Kate Bush]]. Tier 2 (needs confirmation from Paul): Scharmen/Aguilar/Horley/Gibbons/Polidora independent formation; Kennedy's comics-editorial lineage; Chris Adams and Rudy Cortez technical lineages; Joey Ray Hall's formation; Tim Gula's specific life-drawing tradition. Tier 3 (speculative, don't write without confirmation): most figures not yet named.
- ~~Vilppu placement~~ → **Resolved**: Sony San Diego era and after (independent workshop circuit). Not a Blizzard academy entry. Vilppu and Chuck Jones were both Sony-era shared formations with Scharmen.
- **Kate Bush** — does Paul have independent relationship to Kate Bush's work beyond the Tori Amos lineage? Stub currently written; needs confirmation.
- **peak-era field** — needs a retroactive audit pass across existing nodes. New nodes should include it; older nodes mostly don't yet.
- ~~The Amazon-era named relationships~~ → **Substantially resolved**: [[Joey Ray Hall]] hired Paul in (deliberately-chosen mentor figure, followed from Blizzard). [[Chris Adams]] as named tech-artist teacher (Python / systems composition / design patterns; first tech artist Paul cites as a direct influence). [[Rudy Cortez]] as collaborative peer on [[New World]] (BMRT-recognition-token connection, calibrated discretion, low-BS-tolerance shared disposition). Formal ML instructors [[Olcay Boz]] and [[Ali Arsanjani]] looming large; other unnamed ML instructors looming less large. [[First patent application at Amazon]] event captured. Other peers / leads from [[New World]] and marketing roles still open.
- Long-relationship contacts from the [[Flickplay]] / [[Gala Games]] / [[Hypixel Studios]] post-Amazon stretch (per [[high-trust-relationship-architecture]] there are likely more named figures here)
- Maxime / Impossible — characterization beyond the reconnection email
- The remaining post-Amazon studio chapters need stub institution nodes ([[Flickplay]], [[Gala Games]], [[Hypixel Studios]], [[Amazon Game Studios]], [[Sentient Machines]], [[Impossible]])

## Conventions for writing nodes

- Keep the frontmatter accurate; the graph layer reads it.
- Body prose is for what the entity *means*, not biography. Function over CV.
- Wikilink generously. Bridges are the most interesting nodes.
- Mark `status: stub` honestly so future passes know what to flesh out.
- It's fine for nodes to be short. The graph is the artifact, not the prose.
