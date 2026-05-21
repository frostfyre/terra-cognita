---
type: event
tier: self
era: [post-blizzard]
sensitivity: professional
status: drafted
---

# 9-language ML facial and lipsync pipeline

A substantial technical project Paul implemented at [[Amazon Game Studios|Amazon]]. ML-based facial animation and lipsync covering nine languages.

## The technical achievement

Multilingual lipsync is non-trivial work: different languages have different phoneme inventories, different visemes (the visual mouth-shapes corresponding to phonemes), different timing structures. A pipeline that covers nine languages requires phoneme-mapping across all of them, facial animation rigs that work across linguistic registers, ML models that generalize across language data with varying availability and quality.

In the post-Blizzard / pre-current ML-VFX wave, that was real technical contribution.

## The framing that matters more

Paul's own framing of this project:

> *"I implemented a ML based facial and lipsync pipeline that covered 9 languages, **and more importantly** made it useable and readable by wide varieties of stakeholders, designers, producers, programmers and artists."*

The ordering — *more importantly* — is the function-level observation, and it's the core of why this event belongs on the heritage map.

**What Paul valued most about the work was not the underlying ML achievement but the cross-stakeholder usability and readability of the pipeline.**

That's a specific disposition: **building a technical system that legibly serves multiple professional traditions simultaneously**. Designers think differently than programmers, who think differently than artists, who think differently than producers. Most ML pipelines are illegible to at least some of those audiences — they require translation by an intermediary, or they fail to be controllable by non-engineering audiences, or they produce results that one audience can evaluate but others can't.

Paul names, as the *core achievement*, the act of **cross-tradition translation built into the pipeline itself**. The pipeline's value was in its readability across the stakeholder cohort, not just in its ML capability.

## What this opens up on the map

A function-tag the map didn't have explicitly: **`cross-stakeholder-legibility-as-primary-value`** — see [[cross-stakeholder-legibility]] for the full concept treatment.

The disposition of treating *who can understand and use the system* as more important than *what the system technically does*. Real and unusual stance — most engineers value technical capability over legibility, and legibility-first designers often lack the technical depth to build the underlying capability themselves. **Building both, with legibility prioritized, is a specific seam.**

## Connections to other map threads

- **[[Chris Sanders]]'s seam-walker function** — living at the intersection of multiple professional vocabularies (SDCC and SIGGRAPH; narrative and technical-graphics)
- **[[dual-training-convergence]]** — speaking multiple technical languages fluently, including the cross-translation register
- **[[role-authoring]]** — building a system that names itself comprehensibly to multiple audiences is a kind of role-authoring at the artifact level. The pipeline isn't only doing the work; it's also *describing what it's doing in language each audience can read*.

## Implication for the present

The current [[Sentient Machines pipeline|sim2real pipeline]] work has the same property requirement implicit in it. The pipeline serves Harry, the engineering team, future ML researchers who'll consume the data, and Paul himself. Cross-stakeholder legibility is part of what the [[Building the Matrix]] document does at the strategic level, and what the [[pipeline_context.md]] architecture does at the implementation level.

**Paul has been operating in this disposition for years; the Amazon lipsync project is an earlier instance of the same pattern.** Worth holding consciously when articulating the value of the current work in the upcoming positioning conversation.

context:: [[Amazon Game Studios]]
function:: [[cross-stakeholder-legibility]]
sibling-to:: [[Building the Matrix]]
sibling-to:: [[pipeline_context.md]]
