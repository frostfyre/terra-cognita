import Testing
@testable import TerraCognitaKit

/// `AtlasEditor.parseEdgeLine` is the gate that decides whether a
/// single trimmed line is exclusively an edge declaration (and
/// therefore safe for the edge editor to rewrite). False positives
/// would let the editor corrupt prose; false negatives would refuse
/// legitimate edits. These tests pin the boundaries.
@Suite("AtlasEditor.parseEdgeLine")
struct AtlasEditorParseEdgeLineTests {

    @Test("bare wikilink on its own")
    func bareWikilink() {
        let parsed = AtlasEditor.parseEdgeLine("[[Alice]]")
        #expect(parsed?.target == "Alice")
        #expect(parsed?.relationship == nil)
        #expect(parsed?.alias == nil)
    }

    @Test("Dataview prefix")
    func dataviewPrefix() {
        let parsed = AtlasEditor.parseEdgeLine("influenced-by:: [[Alice]]")
        #expect(parsed?.relationship == "influenced-by")
        #expect(parsed?.target == "Alice")
        #expect(parsed?.alias == nil)
    }

    @Test("Dataview prefix with snake_case key")
    func dataviewSnakeCase() {
        let parsed = AtlasEditor.parseEdgeLine("worked_at:: [[Studio Ghibli]]")
        #expect(parsed?.relationship == "worked_at")
        #expect(parsed?.target == "Studio Ghibli")
    }

    @Test("alias preserved")
    func aliasPreserved() {
        let parsed = AtlasEditor.parseEdgeLine("[[alice-smith|Alice Smith]]")
        #expect(parsed?.target == "alice-smith")
        #expect(parsed?.alias == "Alice Smith")
    }

    @Test("alias with Dataview prefix")
    func aliasWithPrefix() {
        let parsed = AtlasEditor.parseEdgeLine("met:: [[alice|Alice]]")
        #expect(parsed?.relationship == "met")
        #expect(parsed?.target == "alice")
        #expect(parsed?.alias == "Alice")
    }

    @Test("prose with embedded wikilink rejected")
    func proseRejected() {
        // The line has content beyond the wikilink — refusing this
        // keeps the editor from mangling sentences like
        // "I met [[Alice]] at the conference."
        #expect(AtlasEditor.parseEdgeLine("I met [[Alice]] at the conference.") == nil)
    }

    @Test("colloquial '::' inside prose rejected")
    func colloquialDoubleColonRejected() {
        // "she said:: ..." is not a Dataview attribute — keys with
        // spaces aren't valid. The line also isn't an exclusive
        // wikilink, so it should be rejected on both grounds.
        #expect(AtlasEditor.parseEdgeLine("she said:: this is great") == nil)
    }

    @Test("Dataview key with space rejected")
    func dataviewKeyWithSpaceRejected() {
        // Valid Dataview keys are barewords (letters/digits/_/-).
        // "she said" contains a space and must not be promoted to
        // a relationship type.
        #expect(AtlasEditor.parseEdgeLine("she said:: [[Alice]]") == nil)
    }

    @Test("empty wikilink rejected")
    func emptyWikilinkRejected() {
        #expect(AtlasEditor.parseEdgeLine("[[]]") == nil)
    }

    @Test("nested brackets rejected")
    func nestedBracketsRejected() {
        // `[[a[[b]]]]` is malformed; refusing prevents heuristic
        // edits to lines we don't fully understand.
        #expect(AtlasEditor.parseEdgeLine("[[a[[b]]]]") == nil)
    }

    @Test("whitespace around the brackets is tolerated by caller")
    func whitespaceIsCallerProblem() {
        // parseEdgeLine assumes its input is pre-trimmed. Lines
        // with leading whitespace are the caller's responsibility
        // to trim. We test the trimmed form here.
        let parsed = AtlasEditor.parseEdgeLine("[[Bob]]")
        #expect(parsed?.target == "Bob")
    }
}
