import Testing
@testable import TerraCognitaKit

/// `AtlasEditor.rewriteEdgeLine` is the in-string surgery that backs
/// `setEdgeRelationship` and `removeEdge`. These tests cover the
/// add-type / clear-type / remove paths plus the disambiguation
/// rules for multi-edge sources.
@Suite("AtlasEditor.rewriteEdgeLine")
struct AtlasEditorRewriteEdgeLineTests {

    @Test("add relationship type to a bare wikilink")
    func addType() {
        let body = "# Note\n\nSome prose.\n\n[[Alice]]\n"
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "Alice",
            oldRelationship: nil,
            newRelationship: "influenced-by",
            removeLine: false
        )
        #expect(result?.contains("influenced-by:: [[Alice]]") == true)
        #expect(result?.contains("\n[[Alice]]\n") == false)
    }

    @Test("change relationship type, preserve alias")
    func changeTypePreserveAlias() {
        let body = "met:: [[alice|Alice]]\n"
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "alice",
            oldRelationship: "met",
            newRelationship: "worked-with",
            removeLine: false
        )
        #expect(result == "worked-with:: [[alice|Alice]]\n")
    }

    @Test("clear relationship type back to bare wikilink")
    func clearType() {
        let body = "influenced-by:: [[Alice]]\n"
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "Alice",
            oldRelationship: "influenced-by",
            newRelationship: nil,
            removeLine: false
        )
        #expect(result == "[[Alice]]\n")
    }

    @Test("remove edge line entirely")
    func removeLine() {
        let body = "# Title\n\nbefore\ninfluenced-by:: [[Alice]]\nafter\n"
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "Alice",
            oldRelationship: "influenced-by",
            newRelationship: nil,
            removeLine: true
        )
        #expect(result == "# Title\n\nbefore\nafter\n")
    }

    @Test("multi-edge disambiguation by relationship type")
    func multiEdgeDisambiguation() {
        // Same source has two edges to Alice with different types.
        // Rewriting "met" must not touch "influenced-by".
        let body = """
        # Note

        met:: [[Alice]]
        influenced-by:: [[Alice]]

        """
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "Alice",
            oldRelationship: "met",
            newRelationship: "worked-with",
            removeLine: false
        )
        #expect(result?.contains("worked-with:: [[Alice]]") == true)
        #expect(result?.contains("influenced-by:: [[Alice]]") == true)
        #expect(result?.contains("met:: [[Alice]]") == false)
    }

    @Test("oldRelationship == nil only matches bare wikilink")
    func nilOldOnlyMatchesBare() {
        // Caller asking for "no type" should not pick a Dataview line.
        let body = "met:: [[Alice]]\n"
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "Alice",
            oldRelationship: nil,
            newRelationship: "worked-with",
            removeLine: false
        )
        #expect(result == nil)
    }

    @Test("prose-embedded wikilinks are refused")
    func proseRefused() {
        let body = "# Note\n\nI met [[Alice]] yesterday.\n"
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "Alice",
            oldRelationship: nil,
            newRelationship: "met",
            removeLine: false
        )
        #expect(result == nil)
    }

    @Test("target matching is case-insensitive")
    func caseInsensitiveTarget() {
        let body = "[[alice]]\n"
        let result = AtlasEditor.rewriteEdgeLine(
            in: body,
            target: "Alice",
            oldRelationship: nil,
            newRelationship: "met",
            removeLine: false
        )
        #expect(result == "met:: [[alice]]\n")
    }
}
