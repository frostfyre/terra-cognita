import Testing
@testable import TerraCognitaKit

/// `MarkdownNoteParser.parse` is the entry point every loaded note
/// passes through. Bugs here ripple into the graph as missing nodes,
/// wrong titles, or invisible bodies. Pinning the cases we've already
/// regressed on.
@Suite("MarkdownNoteParser")
struct MarkdownNoteParserTests {

    @Test("basic frontmatter + title + body")
    func basic() {
        let raw = """
        ---
        type: concept
        ---

        # Influence
        Some body text.
        """
        let parsed = MarkdownNoteParser.parse(raw)
        #expect(parsed.frontMatter["type"] == "concept")
        #expect(parsed.title == "Influence")
        #expect(parsed.body.contains("Some body text."))
    }

    @Test("title pulled from first '# Heading'")
    func titleFromHeading() {
        let parsed = MarkdownNoteParser.parse("# Just a title\n\nbody\n")
        #expect(parsed.title == "Just a title")
    }

    @Test("missing title is nil, not empty")
    func noTitle() {
        let parsed = MarkdownNoteParser.parse("Just some prose with no heading.\n")
        #expect(parsed.title == nil)
    }

    @Test("plain wikilink → unlabelled edge")
    func plainWikilink() {
        let parsed = MarkdownNoteParser.parse("Some text [[Alice]] more text.\n")
        #expect(parsed.links.count == 1)
        #expect(parsed.links.first?.target == "Alice")
        #expect(parsed.links.first?.relationshipType == nil)
    }

    @Test("Dataview line → typed edge")
    func dataviewEdge() {
        let parsed = MarkdownNoteParser.parse("influenced-by:: [[Alice]]\n")
        #expect(parsed.links.count == 1)
        #expect(parsed.links.first?.relationshipType == "influenced-by")
        #expect(parsed.links.first?.target == "Alice")
    }

    @Test("colloquial '::' in prose does not promote to relationship")
    func dataviewKeyValidation() {
        // "she said:: foo" mentions Alice, but the Dataview key is
        // invalid (has a space), so the parser must not promote
        // the wikilink to a typed edge.
        let parsed = MarkdownNoteParser.parse("she said:: hello [[Alice]] today\n")
        #expect(parsed.links.first?.relationshipType == nil)
    }

    @Test("wikilink alias and section anchor are stripped")
    func wikilinkAliasStripped() {
        let parsed = MarkdownNoteParser.parse("[[alice-smith|Alice]] and [[bob#bio|Bob's bio]]\n")
        let targets = parsed.links.map(\.target)
        #expect(targets.contains("alice-smith"))
        #expect(targets.contains("bob"))
    }

    @Test("GEXF-style leading newline before title parses correctly")
    func leadingNewlineBeforeTitle() {
        // Past regression: after stripping frontmatter, body started
        // with "\n# Title" and the title-finder bailed. Verify the
        // title still surfaces.
        let raw = "---\ntype: concept\n---\n\n# Real Title\n\nbody\n"
        let parsed = MarkdownNoteParser.parse(raw)
        #expect(parsed.title == "Real Title")
    }

    @Test("BOM at start of input is stripped")
    func bomStripped() {
        let raw = "\u{FEFF}# Title\n\nbody\n"
        let parsed = MarkdownNoteParser.parse(raw)
        #expect(parsed.title == "Title")
    }

    @Test("CRLF line endings normalize cleanly")
    func crlfNormalized() {
        let raw = "---\r\ntype: concept\r\n---\r\n\r\n# Title\r\nbody\r\n"
        let parsed = MarkdownNoteParser.parse(raw)
        #expect(parsed.frontMatter["type"] == "concept")
        #expect(parsed.title == "Title")
    }
}
