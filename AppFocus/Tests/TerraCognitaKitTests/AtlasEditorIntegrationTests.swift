import Testing
import Foundation
@testable import TerraCognitaKit

/// File-system integration: spin up a tmp directory, write a real
/// `.md`, run the full mutation methods (which open the file, snapshot
/// to `.bak`, rewrite, save), and assert on the resulting bytes.
/// Catches anything the pure-string tests would miss — encoding,
/// snapshot creation, the do/catch wiring in the editor methods.
@Suite("AtlasEditor file I/O integration")
struct AtlasEditorIntegrationTests {

    /// Returns a fresh tmp directory that's cleaned up when `body`
    /// returns. We use the system "item replacement directory" path
    /// (NSFileCoordinator-friendly, auto-cleaned by the OS).
    private func withTmpDir<T>(_ body: (URL) throws -> T) throws -> T {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory
        let url = try fm.url(for: .itemReplacementDirectory,
                             in: .userDomainMask,
                             appropriateFor: parent,
                             create: true)
        defer { try? fm.removeItem(at: url) }
        return try body(url)
    }

    @Test("appendLink round-trip writes a bare wikilink")
    func appendLinkBare() throws {
        try withTmpDir { dir in
            let file = dir.appendingPathComponent("alice.md")
            try "---\ntype: person\n---\n\n# Alice\n\nSome prose.\n"
                .write(to: file, atomically: true, encoding: .utf8)
            var editor = AtlasEditor(atlasURL: dir)
            editor.snapshots = SnapshotTracker()
            let updated = try editor.appendLink(
                in: file,
                target: "Bob",
                relationshipType: nil
            )
            #expect(updated.contains("[[Bob]]"))
            // `.bak` was written on the first edit.
            #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("bak").path))
        }
    }

    @Test("appendLink with Dataview prefix")
    func appendLinkDataview() throws {
        try withTmpDir { dir in
            let file = dir.appendingPathComponent("alice.md")
            try "# Alice\n\nbody\n".write(to: file, atomically: true, encoding: .utf8)
            var editor = AtlasEditor(atlasURL: dir)
            editor.snapshots = SnapshotTracker()
            let updated = try editor.appendLink(
                in: file,
                target: "Bob",
                relationshipType: "knows"
            )
            #expect(updated.contains("knows:: [[Bob]]"))
        }
    }

    @Test("updateEdgeRelationship rewrites the line in place")
    func updateEdgeRelationship() throws {
        try withTmpDir { dir in
            let file = dir.appendingPathComponent("alice.md")
            try "# Alice\n\nmet:: [[Bob]]\n".write(to: file, atomically: true, encoding: .utf8)
            var editor = AtlasEditor(atlasURL: dir)
            editor.snapshots = SnapshotTracker()
            let updated = try editor.updateEdgeRelationship(
                in: file,
                target: "Bob",
                oldRelationship: "met",
                newRelationship: "worked-with"
            )
            #expect(updated.contains("worked-with:: [[Bob]]"))
            #expect(!updated.contains("met:: [[Bob]]"))
        }
    }

    @Test("removeEdge drops the line")
    func removeEdge() throws {
        try withTmpDir { dir in
            let file = dir.appendingPathComponent("alice.md")
            try "# Alice\n\nbefore\nmet:: [[Bob]]\nafter\n"
                .write(to: file, atomically: true, encoding: .utf8)
            var editor = AtlasEditor(atlasURL: dir)
            editor.snapshots = SnapshotTracker()
            let updated = try editor.removeEdge(
                in: file,
                target: "Bob",
                relationshipType: "met"
            )
            #expect(!updated.contains("[[Bob]]"))
            #expect(updated.contains("before"))
            #expect(updated.contains("after"))
        }
    }

    @Test("removeEdge refuses prose-embedded link")
    func removeEdgeRefusesProse() throws {
        try withTmpDir { dir in
            let file = dir.appendingPathComponent("alice.md")
            try "# Alice\n\nI met [[Bob]] yesterday.\n"
                .write(to: file, atomically: true, encoding: .utf8)
            var editor = AtlasEditor(atlasURL: dir)
            editor.snapshots = SnapshotTracker()
            #expect(throws: AtlasEditor.EditError.self) {
                _ = try editor.removeEdge(
                    in: file,
                    target: "Bob",
                    relationshipType: nil
                )
            }
        }
    }

    @Test("snapshot tracker writes .bak only once per file")
    func snapshotOnce() throws {
        try withTmpDir { dir in
            let file = dir.appendingPathComponent("alice.md")
            try "# Alice\n\nbody v1\n".write(to: file, atomically: true, encoding: .utf8)
            let tracker = SnapshotTracker()
            var editor = AtlasEditor(atlasURL: dir)
            editor.snapshots = tracker

            // First edit creates the .bak snapshot of v1.
            _ = try editor.appendLink(in: file, target: "Bob", relationshipType: nil)
            let bakPath = file.appendingPathExtension("bak").path
            let bakV1 = try String(contentsOfFile: bakPath, encoding: .utf8)
            #expect(bakV1.contains("body v1"))

            // Second edit must NOT overwrite the snapshot — the
            // original (pre-AI) state is what the user wants back.
            _ = try editor.appendLink(in: file, target: "Carol", relationshipType: nil)
            let bakStill = try String(contentsOfFile: bakPath, encoding: .utf8)
            #expect(bakStill == bakV1)
        }
    }
}

/// Loader integration: build a tiny atlas on disk and load it back.
@Suite("AtlasLoader load integration")
struct AtlasLoaderIntegrationTests {

    private func withTmpAtlas<T>(_ body: (URL) throws -> T) throws -> T {
        let fm = FileManager.default
        let dir = try fm.url(for: .itemReplacementDirectory,
                             in: .userDomainMask,
                             appropriateFor: fm.temporaryDirectory,
                             create: true)
        defer { try? fm.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("two-node atlas produces two nodes and one edge")
    func twoNodes() throws {
        try withTmpAtlas { dir in
            let alice = dir.appendingPathComponent("alice.md")
            let bob = dir.appendingPathComponent("bob.md")
            try "---\ntype: person\n---\n\n# Alice\n\nknows:: [[bob]]\n"
                .write(to: alice, atomically: true, encoding: .utf8)
            try "---\ntype: person\n---\n\n# Bob\n\nplain body.\n"
                .write(to: bob, atomically: true, encoding: .utf8)
            let (graph, diag) = try AtlasLoader(atlasURL: dir).load()
            #expect(graph.nodes.count == 2)
            #expect(graph.edges.count == 1)
            #expect(diag.mdFilesFound == 2)
            #expect(diag.enumeratorFailed == false)
            let edge = graph.edges.first
            #expect(edge?.relationshipType == "knows")
        }
    }

    @Test("README files are skipped")
    func readmeSkipped() throws {
        try withTmpAtlas { dir in
            let readme = dir.appendingPathComponent("README.md")
            let alice = dir.appendingPathComponent("alice.md")
            try "# README\n\nignored.\n".write(to: readme, atomically: true, encoding: .utf8)
            try "# Alice\n\nbody\n".write(to: alice, atomically: true, encoding: .utf8)
            let (graph, _) = try AtlasLoader(atlasURL: dir).load()
            #expect(graph.nodes.count == 1)
            #expect(graph.nodes["alice"] != nil)
        }
    }

    @Test("dangling wikilink produces a placeholder")
    func placeholderFromDanglingLink() throws {
        try withTmpAtlas { dir in
            let alice = dir.appendingPathComponent("alice.md")
            try "# Alice\n\n[[unknown-target]]\n"
                .write(to: alice, atomically: true, encoding: .utf8)
            let (graph, _) = try AtlasLoader(atlasURL: dir).load()
            // Alice + the synthesized placeholder.
            #expect(graph.nodes.count == 2)
            let placeholder = graph.nodes["unknown-target"]
            #expect(placeholder?.attributes["placeholder"] == "true")
        }
    }
}
