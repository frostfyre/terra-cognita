import Testing
@testable import TerraCognitaKit

/// `splitFrontMatter` and `upsertFrontMatter` are static helpers
/// that every metadata edit (type / era / future fields) flows
/// through. They have to handle the CRLF case and the no-FM-block
/// case without losing body content.
@Suite("AtlasEditor front-matter helpers")
struct AtlasEditorFrontMatterTests {

    // MARK: - splitFrontMatter

    @Test("LF-only front matter block")
    func splitFrontMatterLF() {
        let raw = """
        ---
        type: concept
        era: childhood
        ---

        # Title

        body
        """
        let (fm, body) = AtlasEditor.splitFrontMatter(raw)
        #expect(fm == "type: concept\nera: childhood")
        // splitFrontMatter only eats one newline after the closing
        // fence — the blank line between fence and `# Title` stays
        // in the body. The loader's `MarkdownNoteParser` handles
        // the extra newline; splitFrontMatter doesn't.
        #expect(body.contains("# Title"))
        #expect(body.contains("body"))
    }

    @Test("CRLF front matter block")
    func splitFrontMatterCRLF() {
        let raw = "---\r\ntype: concept\r\n---\r\n\r\n# Title\r\n"
        let (fm, body) = AtlasEditor.splitFrontMatter(raw)
        // splitFrontMatter searches for `\n---`, so the matched
        // newline before the closing fence includes the carriage
        // return that preceded it. The trailing `\r` on the FM
        // string is then the caller's problem to trim — document
        // the current behavior so a future cleanup is intentional.
        #expect(fm?.trimmingCharacters(in: .whitespacesAndNewlines) == "type: concept")
        #expect(body.contains("# Title"))
    }

    @Test("no front matter returns nil + full raw")
    func splitFrontMatterMissing() {
        let raw = "# Just a title\n\nbody\n"
        let (fm, body) = AtlasEditor.splitFrontMatter(raw)
        #expect(fm == nil)
        #expect(body == raw)
    }

    @Test("malformed front matter (no closing fence)")
    func splitFrontMatterMalformed() {
        // No closing `---` → treat the whole thing as body.
        let raw = "---\ntype: concept\n# Title\n\nbody\n"
        let (fm, body) = AtlasEditor.splitFrontMatter(raw)
        #expect(fm == nil)
        #expect(body == raw)
    }

    @Test("body containing --- is preserved")
    func splitFrontMatterTripleDashInBody() {
        let raw = """
        ---
        type: concept
        ---

        # Title

        Some text
        ---
        more text
        """
        let (fm, body) = AtlasEditor.splitFrontMatter(raw)
        #expect(fm == "type: concept")
        #expect(body.contains("Some text"))
        #expect(body.contains("more text"))
    }

    // MARK: - upsertFrontMatter

    @Test("upsert existing key replaces value")
    func upsertExisting() {
        let raw = """
        ---
        type: concept
        era: childhood
        ---

        body
        """
        let updated = AtlasEditor.upsertFrontMatter(in: raw, key: "era", value: "adolescence")
        #expect(updated.contains("era: adolescence"))
        #expect(!updated.contains("era: childhood"))
        #expect(updated.contains("type: concept"))
    }

    @Test("upsert missing key appends to FM")
    func upsertMissing() {
        let raw = """
        ---
        type: concept
        ---

        body
        """
        let updated = AtlasEditor.upsertFrontMatter(in: raw, key: "era", value: "childhood")
        #expect(updated.contains("type: concept"))
        #expect(updated.contains("era: childhood"))
    }

    @Test("upsert into note with no front-matter block creates one")
    func upsertCreatesBlock() {
        let raw = "# Title\n\nbody\n"
        let updated = AtlasEditor.upsertFrontMatter(in: raw, key: "type", value: "concept")
        #expect(updated.hasPrefix("---\ntype: concept\n---"))
        #expect(updated.contains("# Title"))
        #expect(updated.contains("body"))
    }

    @Test("upsert preserves body content")
    func upsertPreservesBody() {
        let raw = """
        ---
        type: concept
        ---

        # Title

        First line.
        Second line.
        """
        let updated = AtlasEditor.upsertFrontMatter(in: raw, key: "era", value: "1980s")
        #expect(updated.contains("First line."))
        #expect(updated.contains("Second line."))
    }
}
