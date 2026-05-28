import Foundation
import SwiftUI

// Minimal graph container that GraphCanvasView expects.
@MainActor
public final class GraphStore: ObservableObject {
    @Published var graph: Graph
    @Published var loadStatus: String = ""
    /// Recent vaults the user has opened. Mutated when a load
    /// succeeds; persisted to UserDefaults.
    @Published var library: VaultLibrary

    /// The currently-active vault folder if it's writable. `nil` while
    /// the app is showing the bundled Miyazaki demo (bundle resources
    /// are read-only). Drives `canIngest`.
    @Published var writableVaultURL: URL?

    /// Per-vault ontology (custom types + eras). Falls back to
    /// `VaultConfig.default` for vaults that don't declare a config.
    @Published var config: VaultConfig = .default

    /// True if node ingestion is allowed against the current vault.
    var canIngest: Bool { writableVaultURL != nil }

    /// Per-store `.bak` snapshot tracker. Was a process-global static
    /// on `VaultEditor`; lives here so each `GraphStore` (current
    /// usage: one per session, future usage: potentially per-vault)
    /// gets its own scope. Reference type so the value-typed
    /// `VaultEditor` can hold a shared handle.
    private let snapshots = SnapshotTracker()

    /// Construct a `VaultEditor` wired to this store's snapshot
    /// tracker. Every mutation site in GraphStore should route
    /// through here so they all share the same `.bak`-once-per-file
    /// semantics.
    private func makeEditor(_ vaultURL: URL) -> VaultEditor {
        var editor = VaultEditor(vaultURL: vaultURL)
        editor.snapshots = snapshots
        return editor
    }

    /// Empty store. The app's `GraphView` calls `loadDefaultVault()` to
    /// populate it from the heritage vault on disk.
    public init() {
        self.graph = Graph(nodes: [:], edges: [])
        self.library = VaultLibrary.load()
    }

    init(graph: Graph) {
        self.graph = graph
        self.library = VaultLibrary.load()
    }

    /// Loads the default vault: previously-bookmarked user folder if
    /// one is saved, otherwise the bundled Miyazaki demo, otherwise the
    /// development heritage vault on disk.
    func loadDefaultVault() {
        if let url = VaultBookmark.load() {
            load(from: url, fromBookmark: true)
        } else {
            Task {
                do {
                    let (vaultName, g, isWritable, url) = try await Self.loadFromDefaultVault()
                    self.graph = g
                    self.config = VaultConfig.load(from: url)
                    self.loadStatus = "Loaded \(g.nodes.count) nodes / \(g.edges.count) edges from \(vaultName)"
                    self.writableVaultURL = isWritable ? url : nil
                } catch VaultError.notFound {
                    self.loadStatus = "Vault not found — looked relative to CWD and the executable directory."
                    self.writableVaultURL = nil
                } catch {
                    self.loadStatus = "Vault load failed: \(error.localizedDescription)"
                    self.writableVaultURL = nil
                }
            }
        }
    }

    /// Load a vault from a user-chosen folder URL. Manages the
    /// security-scoped resource, saves a current-vault bookmark, and
    /// touches the recent-vaults library.
    func load(from url: URL, fromBookmark: Bool = false) {
        let didStart = url.startAccessingSecurityScopedResource()
        Task {
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                // Load the config first so the loader's extractor
                // toggles + custom types come into play during the walk.
                let cfg = VaultConfig.load(from: url)
                let (g, diag) = try await Task.detached(priority: .userInitiated) {
                    try Self.coordinatedLoad(at: url, config: cfg)
                }.value
                self.graph = g
                self.config = cfg
                if g.nodes.isEmpty {
                    // Explain *why* the load came back empty so the
                    // user can act — most often this is a wrong-folder
                    // pick on iOS (parent of the actual vault) or a
                    // sandbox failure if the picker URL didn't grant
                    // recursive read access.
                    if diag.enumeratorFailed {
                        self.loadStatus = "Couldn't read \(url.lastPathComponent) — folder access was denied. Try picking the folder again."
                    } else if diag.itemsWalked == 0 {
                        self.loadStatus = "Loaded 0 nodes from \(url.lastPathComponent) — the folder appears to be empty."
                    } else if diag.mdFilesFound == 0 {
                        self.loadStatus = "Loaded 0 nodes from \(url.lastPathComponent) — walked \(diag.itemsWalked) items but found no .md files. Did you pick the parent folder?"
                    } else {
                        self.loadStatus = "Loaded 0 nodes from \(url.lastPathComponent) — walked \(diag.itemsWalked) items, \(diag.mdFilesFound) .md files but none parsed."
                    }
                } else {
                    self.loadStatus = "Loaded \(g.nodes.count) nodes / \(g.edges.count) edges from \(url.lastPathComponent)"
                }
                self.writableVaultURL = url
                if !fromBookmark {
                    VaultBookmark.save(url)
                }
                self.library.touch(url,
                                   nodeCount: g.nodes.count,
                                   edgeCount: g.edges.count)
                self.library.save()
            } catch {
                self.loadStatus = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
                self.writableVaultURL = nil
            }
        }
    }

    /// Open a recent-vaults library entry. Resolves the saved bookmark
    /// and routes through `load(from:)`.
    func openLibraryEntry(_ entryID: UUID) {
        if let url = library.resolve(entryID: entryID) {
            library.save()
            load(from: url)
        } else {
            loadStatus = "Couldn't resolve that vault — the folder may have moved."
            library.remove(entryID: entryID)
            library.save()
        }
    }

    /// Drop an entry from the recent-vaults library.
    func forgetLibraryEntry(_ entryID: UUID) {
        library.remove(entryID: entryID)
        library.save()
    }

    /// Forget the user-chosen vault and revert to the default search.
    func resetToDefaultVault() {
        VaultBookmark.clear()
        loadDefaultVault()
    }

    // MARK: - Ingestion

    /// Result of a node-creation attempt.
    enum CreateError: LocalizedError {
        case noWritableVault
        case writer(VaultWriter.WriteError)
        /// A node with a normalized-equal label already exists. The
        /// associated value is the existing node's id so the UI can
        /// offer "Open existing instead".
        case duplicate(existingID: String)

        var errorDescription: String? {
            switch self {
            case .noWritableVault:
                return "Open or create a writable vault folder first."
            case .writer(let inner):
                return inner.errorDescription
            case .duplicate(let id):
                return "A node named \"\(id)\" already exists."
            }
        }
    }

    /// Normalize a label / id for duplicate detection. Lowercases and
    /// strips whitespace, hyphens, and underscores so that
    /// "Usenet job posting" ≈ "usenet-job-posting" ≈ "usenet_job_posting".
    static func normalizedSlug(_ raw: String) -> String {
        raw.lowercased().unicodeScalars.reduce(into: "") { acc, s in
            switch s {
            case " ", "\t", "-", "_": return
            default: acc.unicodeScalars.append(s)
            }
        }
    }

    /// Create a new node in the active vault. Writes a markdown file with
    /// matching front-matter / title / body, then appends a `Node` to the
    /// in-memory graph immediately so the canvas can frame it without
    /// waiting for a re-scan. Returns the new node's id on success.
    @discardableResult
    func createNode(label: String,
                    type: String?,
                    era: String?,
                    body: String,
                    isPrivate: Bool = false) -> Result<String, CreateError> {
        guard let vaultURL = writableVaultURL else {
            return .failure(.noWritableVault)
        }

        // Compose-time dedup: refuse the write if a node with a
        // normalized-equal label already exists, and hand back the
        // existing id so the composer can offer "Open instead".
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposedNorm = Self.normalizedSlug(trimmed)
        if !proposedNorm.isEmpty {
            for (id, node) in graph.nodes {
                if Self.normalizedSlug(id) == proposedNorm
                    || Self.normalizedSlug(node.label) == proposedNorm {
                    return .failure(.duplicate(existingID: id))
                }
            }
        }

        let writer = VaultWriter(vaultURL: vaultURL)
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        do {
            let (fileURL, slug) = try writer.createNote(
                label: label,
                type: type,
                era: era,
                body: body,
                isPrivate: isPrivate
            )

            // Append to the in-memory graph. The id is the file's
            // basename (matching VaultLoader). Resolve any wikilinks in
            // the body so the new node arrives with edges already wired.
            var node = Node(id: slug, label: label.trimmingCharacters(in: .whitespacesAndNewlines))
            var attrs: [String: String] = [:]
            if let type, !type.isEmpty { attrs["type"] = type }
            if let era,  !era.isEmpty  { attrs["era"]  = era }
            if let sub = type.flatMap(VaultWriter.subfolder(for:)) {
                attrs["folder"] = sub
            }
            if isPrivate { attrs["private"] = "true" }
            node.attributes = attrs
            node.filePath = fileURL.path
            node.markdownContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""

            graph.nodes[slug] = node

            // Wire edges from inline `[[wikilinks]]` in the body. Only
            // edges whose target already exists in the graph are added
            // — dangling links remain in the body, ready to resolve if
            // their target is ever created.
            let parsed = MarkdownNoteParser.extractLinks(body)
            var seen: Set<String> = []
            var slugIndex: [String: String] = [:]
            for id in graph.nodes.keys { slugIndex[id.lowercased()] = id }
            for link in parsed {
                guard let targetID = slugIndex[link.target.lowercased()],
                      targetID != slug else { continue }
                let edgeID = "\(slug)->\(targetID)\(link.relationshipType.map { "::\($0)" } ?? "")"
                if seen.contains(edgeID) { continue }
                seen.insert(edgeID)
                var edge = Edge(id: edgeID, sourceID: slug, targetID: targetID)
                edge.relationshipType = link.relationshipType
                graph.edges.append(edge)
            }

            loadStatus = "Created \"\(node.label)\""
            return .success(slug)
        } catch let err as VaultWriter.WriteError {
            return .failure(.writer(err))
        } catch {
            return .failure(.writer(.writeFailed(error.localizedDescription)))
        }
    }

    /// Apply an AI-proposed mutation against the node with id `nodeID`.
    /// Returns `nil` on success or a user-readable error string on
    /// failure. The in-memory graph is updated to match the on-disk
    /// write so the canvas reflects the change without a re-scan.
    @discardableResult
    func applyProposal(_ proposal: NodeProposal, to nodeID: String) -> String? {
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        guard var node = graph.nodes[nodeID] else {
            return "Selected node no longer exists."
        }
        guard let pathString = node.filePath else {
            return "Selected node has no backing file."
        }
        let fileURL = URL(fileURLWithPath: pathString)
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        let editor = makeEditor(vaultURL)
        do {
            switch proposal.kind {
            case .addLink(let target, let rel):
                let updated = try editor.appendLink(in: fileURL,
                                                    target: target,
                                                    relationshipType: rel)
                node.markdownContent = updated
                graph.nodes[nodeID] = node
                // Wire the in-memory edge if the target resolves.
                wireEdge(from: nodeID, to: target, relationshipType: rel)

            case .createLinkedNode(let label, let type, let era, let rel):
                // Create the new node first; if that fails, abort.
                let create = createNode(label: label, type: type, era: era, body: "")
                switch create {
                case .failure(let err):
                    return err.errorDescription ?? "Couldn't create node."
                case .success(let newID):
                    // Append link from current node → new node.
                    let updated = try editor.appendLink(in: fileURL,
                                                        target: label,
                                                        relationshipType: rel)
                    node.markdownContent = updated
                    graph.nodes[nodeID] = node
                    wireEdge(from: nodeID, to: newID, relationshipType: rel)
                }

            case .setFrontMatter(let key, let value):
                let updated = try editor.setFrontMatter(in: fileURL,
                                                        key: key,
                                                        value: value)
                node.markdownContent = updated
                node.attributes[key] = value
                graph.nodes[nodeID] = node

            case .replaceBody(let newBody):
                let updated = try editor.replaceBody(in: fileURL,
                                                     newBody: newBody)
                node.markdownContent = updated
                graph.nodes[nodeID] = node
            }
            return nil
        } catch let err as VaultEditor.EditError {
            return err.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    /// Replace the body of an existing node with `newBody`. Frontmatter
    /// is preserved by `VaultEditor.replaceBody`. The caller is expected
    /// to include the `# Title` heading line if they want one — the
    /// inspector's edit flow stitches the node's display label back in
    /// before calling this so the title stays intact across round-trips.
    ///
    /// When the node has no backing file yet (Constellation-created or
    /// otherwise materialized-in-memory-only), we create one via
    /// `VaultWriter` first using the node's current type / era / label,
    /// then write the body into it. The node's `filePath` is patched
    /// in place so subsequent edits go through the normal path.
    @discardableResult
    func updateNodeBody(_ nodeID: String, body newBody: String) -> String? {
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        guard var node = graph.nodes[nodeID] else {
            return "Selected node no longer exists."
        }
        return vaultURL.withSecurityScope {
            let editor = makeEditor(vaultURL)
            let fileURL: URL
            if let pathString = node.filePath {
                fileURL = URL(fileURLWithPath: pathString)
            } else {
                // No backing file yet — materialize one. We write an empty
                // body first so `VaultWriter` sets up the front-matter and
                // picks the right subfolder for the type; `replaceBody`
                // below then fills in the user's content.
                let writer = VaultWriter(vaultURL: vaultURL)
                do {
                    let created = try writer.createNote(
                        label: node.label,
                        type: node.type,
                        era: node.era,
                        body: ""
                    )
                    fileURL = created.fileURL
                    node.filePath = created.fileURL.path
                } catch let err as VaultWriter.WriteError {
                    return err.errorDescription
                } catch {
                    return error.localizedDescription
                }
            }

            do {
                let updated = try editor.replaceBody(in: fileURL, newBody: newBody)
                node.markdownContent = updated
                graph.nodes[nodeID] = node
                return nil
            } catch let err as VaultEditor.EditError {
                return err.errorDescription
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// Promote a synthetic placeholder node (created by the loader's
    /// dangling-wikilink extractor) to a real, typed node backed by
    /// a fresh `.md` file. The new file lands in the subfolder
    /// implied by `typeName` (per `VaultWriter.subfolder(for:)`) with
    /// the placeholder's label as the title. Edges that pointed at
    /// the placeholder id are re-targeted to the new slug.
    ///
    /// Returns the new node id on success, or a user-readable error
    /// string on failure. The caller (the inspector) re-selects the
    /// new node so focus is preserved across the slug rename.
    func promoteNode(_ placeholderID: String,
                     to typeName: String) -> Result<String, NodeError> {
        guard let vaultURL = writableVaultURL else {
            return .failure(.message("Open or create a writable vault first."))
        }
        guard let placeholder = graph.nodes[placeholderID] else {
            return .failure(.message("Node no longer exists."))
        }
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        let writer = VaultWriter(vaultURL: vaultURL)
        let created: (fileURL: URL, slug: String)
        do {
            created = try writer.createNote(
                label: placeholder.label,
                type: typeName.lowercased(),
                era: nil,
                body: ""
            )
        } catch let err as VaultWriter.WriteError {
            return .failure(.message(err.errorDescription
                                     ?? "Couldn't create note."))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
        let newID = created.slug

        // Build the new node — inherit the placeholder's label and
        // any user-set attributes the loader may have stashed
        // alongside the synthetic markers (we drop the placeholder /
        // synthetic flags since this is now a real node).
        var newNode = Node(id: newID, label: placeholder.label)
        var attrs = placeholder.attributes
        attrs["type"] = typeName.lowercased()
        attrs.removeValue(forKey: "placeholder")
        attrs.removeValue(forKey: "synthetic")
        newNode.attributes = attrs
        newNode.filePath = created.fileURL.path

        // Re-target edges if the slug changed. Edge.id is derived
        // from `source->target::relationshipType` so a renamed
        // endpoint also needs a new id.
        if newID != placeholderID {
            graph.nodes[newID] = newNode
            graph.nodes.removeValue(forKey: placeholderID)
            for i in 0..<graph.edges.count {
                let e = graph.edges[i]
                let needsSrc = e.sourceID == placeholderID
                let needsTgt = e.targetID == placeholderID
                guard needsSrc || needsTgt else { continue }
                let newSrc = needsSrc ? newID : e.sourceID
                let newTgt = needsTgt ? newID : e.targetID
                let relSuffix = e.relationshipType.map { "::\($0)" } ?? ""
                var rewritten = Edge(
                    id: "\(newSrc)->\(newTgt)\(relSuffix)",
                    sourceID: newSrc,
                    targetID: newTgt
                )
                rewritten.relationshipType = e.relationshipType
                rewritten.confidence = e.confidence
                rewritten.provenance = e.provenance
                rewritten.evidence = e.evidence
                rewritten.era = e.era
                rewritten.date = e.date
                graph.edges[i] = rewritten
            }
        } else {
            graph.nodes[newID] = newNode
        }
        return .success(newID)
    }

    /// Generic node-mutation error type. Wraps a user-readable
    /// message so callers can display it inline. Used by
    /// `promoteNode` today; older paths return `String?` directly.
    enum NodeError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let m): return m }
        }
    }

    /// Update (or clear) the `era:` front-matter on an existing node.
    /// Passing `nil` or an empty string removes the key. Returns `nil`
    /// on success or a user-readable error.
    @discardableResult
    func setEra(in nodeID: String, to era: String?) -> String? {
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        guard var node = graph.nodes[nodeID] else {
            return "Selected node no longer exists."
        }
        guard let pathString = node.filePath else {
            return "Selected node has no backing file."
        }
        let fileURL = URL(fileURLWithPath: pathString)
        return vaultURL.withSecurityScope {
            let editor = makeEditor(vaultURL)
            let trimmed = era?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            do {
                // VaultEditor.setFrontMatter is upsert-only; setting to an
                // empty string is fine for our purposes (the loader treats
                // empty era the same as missing era).
                let updated = try editor.setFrontMatter(in: fileURL,
                                                        key: "era",
                                                        value: trimmed)
                node.markdownContent = updated
                if trimmed.isEmpty {
                    node.attributes.removeValue(forKey: "era")
                } else {
                    node.attributes["era"] = trimmed
                }
                graph.nodes[nodeID] = node
                return nil
            } catch let err as VaultEditor.EditError {
                return err.errorDescription
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// Update the `type:` front-matter on an existing node. The
    /// physical file does NOT move between subfolders — that would
    /// invalidate every wikilink pointing at it and break the
    /// loader's path-based id derivation. Type is just a metadata
    /// reclassification; the file stays put. If the node has no
    /// backing file yet (Constellation-created), one is materialized
    /// via `VaultWriter.createNote` first, same pattern as
    /// `updateNodeBody`.
    @discardableResult
    func setType(in nodeID: String, to typeName: String) -> String? {
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        guard var node = graph.nodes[nodeID] else {
            return "Selected node no longer exists."
        }
        return vaultURL.withSecurityScope {
            let editor = makeEditor(vaultURL)
            let fileURL: URL
            if let pathString = node.filePath {
                fileURL = URL(fileURLWithPath: pathString)
            } else {
                let writer = VaultWriter(vaultURL: vaultURL)
                do {
                    let created = try writer.createNote(
                        label: node.label,
                        type: typeName.lowercased(),
                        era: node.era,
                        body: ""
                    )
                    fileURL = created.fileURL
                    node.filePath = created.fileURL.path
                } catch let err as VaultWriter.WriteError {
                    return err.errorDescription
                } catch {
                    return error.localizedDescription
                }
            }
            do {
                let updated = try editor.setFrontMatter(in: fileURL,
                                                        key: "type",
                                                        value: typeName.lowercased())
                node.markdownContent = updated
                node.attributes["type"] = typeName.lowercased()
                // If this was a synthetic placeholder, the markers are now stale.
                node.attributes.removeValue(forKey: "placeholder")
                node.attributes.removeValue(forKey: "synthetic")
                graph.nodes[nodeID] = node
                return nil
            } catch let err as VaultEditor.EditError {
                return err.errorDescription
            } catch {
                return error.localizedDescription
            }
        }
    }

    // MARK: - Edge editing

    /// Rewrite the `relationshipType` on an existing edge. The edit
    /// happens in the **source** note's markdown (Dataview-style
    /// `key:: [[target]]` line). Returns `nil` on success, a
    /// user-facing error message otherwise.
    ///
    /// Only edges whose body line is *exclusively* a wikilink (with
    /// optional Dataview prefix) are editable here — wikilinks
    /// embedded mid-prose are flagged with a hint to edit the
    /// source note manually.
    @discardableResult
    func setEdgeRelationship(_ edge: Edge, to newRelationship: String?) -> String? {
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        guard let sourceNode = graph.nodes[edge.sourceID],
              let pathString = sourceNode.filePath else {
            return "Source note has no backing file."
        }
        guard let targetNode = graph.nodes[edge.targetID] else {
            return "Target node no longer exists."
        }
        let fileURL = URL(fileURLWithPath: pathString)
        return vaultURL.withSecurityScope {
            let editor = makeEditor(vaultURL)
            let trimmedNew = newRelationship?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveNew = (trimmedNew?.isEmpty == true) ? nil : trimmedNew
            do {
                _ = try editor.updateEdgeRelationship(
                    in: fileURL,
                    target: targetNode.id,
                    oldRelationship: edge.relationshipType,
                    newRelationship: effectiveNew
                )
                // Mirror the change in memory: edge id encodes the
                // relationship type, so remove the old edge and add a
                // freshly-built one with the new id.
                graph.edges.removeAll { $0.id == edge.id }
                let suffix = effectiveNew.map { "::\($0)" } ?? ""
                let newID = "\(edge.sourceID)->\(edge.targetID)\(suffix)"
                var rebuilt = Edge(id: newID,
                                   sourceID: edge.sourceID,
                                   targetID: edge.targetID)
                rebuilt.relationshipType = effectiveNew
                rebuilt.confidence = edge.confidence
                rebuilt.provenance = edge.provenance
                rebuilt.evidence = edge.evidence
                rebuilt.era = edge.era
                rebuilt.date = edge.date
                graph.edges.append(rebuilt)
                return nil
            } catch let err as VaultEditor.EditError {
                return err.errorDescription
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// Delete an edge by removing its declaration line from the
    /// source note. Same restrictions as `setEdgeRelationship` —
    /// only bare edge lines are editable.
    @discardableResult
    func removeEdge(_ edge: Edge) -> String? {
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        guard let sourceNode = graph.nodes[edge.sourceID],
              let pathString = sourceNode.filePath else {
            return "Source note has no backing file."
        }
        guard let targetNode = graph.nodes[edge.targetID] else {
            return "Target node no longer exists."
        }
        let fileURL = URL(fileURLWithPath: pathString)
        return vaultURL.withSecurityScope {
            let editor = makeEditor(vaultURL)
            do {
                _ = try editor.removeEdge(
                    in: fileURL,
                    target: targetNode.id,
                    relationshipType: edge.relationshipType
                )
                graph.edges.removeAll { $0.id == edge.id }
                return nil
            } catch let err as VaultEditor.EditError {
                return err.errorDescription
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// Materialize a Capture proposal: creates each accepted node, then
    /// wires the wikilinks (internal between new nodes + external to
    /// existing graph nodes) by appending them to each new node's body.
    /// Returns the id of the first successfully-created node so the
    /// caller can select + frame it on the canvas.
    @discardableResult
    func applyConstellation(_ constellation: Constellation) -> String? {
        let accepted = constellation.nodes.filter { $0.accepted }
        guard !accepted.isEmpty else { return nil }
        guard writableVaultURL != nil else {
            loadStatus = "Open or create a writable vault first."
            return nil
        }

        // Phase 1: create the new nodes. Track label → new-id so we can
        // resolve internal links in phase 2 even when the model
        // proposed labels that got disambiguated by the dedup check.
        var newLabelToID: [String: String] = [:]
        var firstCreatedID: String?
        var created: [(label: String, id: String, links: [String])] = []
        for node in accepted {
            // Combine internal + external links into a single list of
            // wikilinks to append once the bodies are settled.
            let combinedLinks = node.linksToNew + node.linksToExisting
            let result = createNode(
                label: node.label,
                type: node.type,
                era: node.era,
                body: node.body
            )
            switch result {
            case .success(let id):
                newLabelToID[node.label.lowercased()] = id
                if firstCreatedID == nil { firstCreatedID = id }
                created.append((node.label, id, combinedLinks))
            case .failure(.duplicate(let existingID)):
                // Treat the existing node as the materialization of
                // this proposal — fold its outgoing links onto it.
                newLabelToID[node.label.lowercased()] = existingID
                created.append((node.label, existingID, combinedLinks))
            case .failure(let err):
                loadStatus = "Couldn't create \"\(node.label)\": \(err.errorDescription ?? "")"
            }
        }

        // Phase 2: append wikilinks. We resolve each link via the
        // newLabelToID map first (to catch internal links between just-
        // created nodes), then fall back to the existing graph.
        guard let vaultURL = writableVaultURL else { return firstCreatedID }
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }
        let editor = makeEditor(vaultURL)

        for (_, sourceID, links) in created {
            guard var node = graph.nodes[sourceID],
                  let path = node.filePath else { continue }
            let fileURL = URL(fileURLWithPath: path)
            for rawTarget in links {
                // Resolve the link target: prefer new nodes (so
                // internal links work even when label was tweaked),
                // then fall back to existing graph match.
                let targetID = newLabelToID[rawTarget.lowercased()]
                    ?? graph.nodes.values.first(where: { $0.label.lowercased() == rawTarget.lowercased() })?.id
                    ?? graph.nodes.keys.first(where: { $0.lowercased() == rawTarget.lowercased() })
                guard let tid = targetID, tid != sourceID else { continue }
                guard let target = graph.nodes[tid] else { continue }

                do {
                    let updated = try editor.appendLink(in: fileURL,
                                                        target: target.label,
                                                        relationshipType: nil)
                    node.markdownContent = updated
                    graph.nodes[sourceID] = node
                    wireEdge(from: sourceID, to: target.label, relationshipType: nil)
                } catch {
                    // Log and continue — one bad link shouldn't sink
                    // the whole constellation.
                    print("applyConstellation appendLink failed: \(error)")
                }
            }
        }
        loadStatus = "Captured \(created.count) node\(created.count == 1 ? "" : "s")."
        return firstCreatedID
    }

    /// Delete a node: removes its `.md` file (if present) and drops the
    /// node + every edge touching it from the in-memory graph. Wikilinks
    /// to it in other files are left in place — the loader already
    /// tolerates dangling links, and rewriting every file in the vault
    /// is the merge operation's responsibility, not delete's.
    /// Returns `nil` on success or a user-readable error.
    @discardableResult
    func deleteNode(_ nodeID: String) -> String? {
        guard let node = graph.nodes[nodeID] else {
            return "Node not found."
        }
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        if let path = node.filePath {
            let fileURL = URL(fileURLWithPath: path)
            // Snapshot the file before deleting in case the user wants
            // it back — same .bak convention VaultEditor uses.
            if let raw = try? String(contentsOf: fileURL, encoding: .utf8) {
                let bak = fileURL.appendingPathExtension("bak")
                try? raw.write(to: bak, atomically: true, encoding: .utf8)
            }
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                return "Couldn't delete file: \(error.localizedDescription)"
            }
        }
        graph.nodes.removeValue(forKey: nodeID)
        graph.edges.removeAll { $0.sourceID == nodeID || $0.targetID == nodeID }
        loadStatus = "Deleted \"\(node.label)\""
        return nil
    }

    /// Merge `loserID` into `winnerID`:
    ///   1. Append loser's body onto winner's body (with a separator).
    ///   2. Rewrite every `[[loser]]` wikilink across the entire vault
    ///      to point at the winner's label.
    ///   3. Delete loser's .md file.
    ///   4. Re-target/re-source loser's in-memory edges onto winner.
    /// Returns `nil` on success or a user-readable error.
    @discardableResult
    func mergeNode(_ loserID: String, into winnerID: String) -> String? {
        guard loserID != winnerID else { return "Can't merge a node into itself." }
        guard let loser = graph.nodes[loserID],
              let winner = graph.nodes[winnerID] else { return "Both nodes must exist." }
        guard let vaultURL = writableVaultURL else {
            return "Open or create a writable vault first."
        }
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        // 1. Append loser's body to winner's body (file write).
        if let winnerPath = winner.filePath,
           let loserBody = loser.markdownContent,
           let winnerRaw = try? String(contentsOf: URL(fileURLWithPath: winnerPath), encoding: .utf8) {
            let (fm, winnerBody) = VaultEditor.splitFrontMatter(winnerRaw)
            let (_, loserBodyStripped) = VaultEditor.splitFrontMatter(loserBody)
            var merged = ""
            if let fm, !fm.isEmpty { merged += "---\n\(fm)\n---\n\n" }
            merged += winnerBody.trimmingCharacters(in: .whitespacesAndNewlines)
            merged += "\n\n---\n\n*Merged from [[\(loser.label)]]:*\n\n"
            merged += loserBodyStripped.trimmingCharacters(in: .whitespacesAndNewlines)
            merged += "\n"
            do {
                try winnerRaw.write(to: URL(fileURLWithPath: winnerPath).appendingPathExtension("bak"),
                                    atomically: true, encoding: .utf8)
                try merged.write(to: URL(fileURLWithPath: winnerPath),
                                 atomically: true, encoding: .utf8)
                var updated = winner
                updated.markdownContent = merged
                graph.nodes[winnerID] = updated
            } catch {
                return "Couldn't append loser body to winner: \(error.localizedDescription)"
            }
        }

        // 2. Rewrite [[loser]] → [[winner]] across every .md in the vault.
        let rewriteCount = Self.rewriteWikilinks(
            in: vaultURL,
            from: loser.label,
            to: winner.label,
            skipping: loser.filePath.map { URL(fileURLWithPath: $0) }
        )

        // 3. Delete loser's .md file (with .bak snapshot).
        if let loserPath = loser.filePath {
            let loserURL = URL(fileURLWithPath: loserPath)
            if let raw = try? String(contentsOf: loserURL, encoding: .utf8) {
                try? raw.write(to: loserURL.appendingPathExtension("bak"),
                               atomically: true, encoding: .utf8)
            }
            try? FileManager.default.removeItem(at: loserURL)
        }

        // 4. Re-target / re-source in-memory edges; drop self-loops.
        var newEdges: [Edge] = []
        var seen: Set<String> = []
        for edge in graph.edges {
            var e = edge
            if e.sourceID == loserID { e = Edge(id: edge.id, sourceID: winnerID, targetID: e.targetID) }
            if e.targetID == loserID { e = Edge(id: e.id,    sourceID: e.sourceID, targetID: winnerID) }
            if e.sourceID == e.targetID { continue }
            let key = "\(e.sourceID)->\(e.targetID)\(edge.relationshipType.map { "::\($0)" } ?? "")"
            if seen.contains(key) { continue }
            seen.insert(key)
            var rebuilt = Edge(id: key, sourceID: e.sourceID, targetID: e.targetID)
            rebuilt.relationshipType = edge.relationshipType
            rebuilt.confidence = edge.confidence
            rebuilt.provenance = edge.provenance
            newEdges.append(rebuilt)
        }
        graph.edges = newEdges
        graph.nodes.removeValue(forKey: loserID)

        loadStatus = "Merged \"\(loser.label)\" into \"\(winner.label)\" — \(rewriteCount) cross-vault links rewritten"
        return nil
    }

    /// Walk every `.md` in `vaultURL` and rewrite `[[oldLabel]]` to
    /// `[[newLabel]]` (case-insensitive match on the inner content).
    /// Returns the total number of replacements made. Skips `skipping`
    /// so we don't rewrite the file we're about to delete.
    private static func rewriteWikilinks(in vaultURL: URL,
                                         from oldLabel: String,
                                         to newLabel: String,
                                         skipping: URL?) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: vaultURL,
                                             includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else {
            return 0
        }
        var totalReplacements = 0
        let pattern = NSRegularExpression.escapedPattern(for: oldLabel)
        // [[oldLabel]] or [[oldLabel|alias]] or [[oldLabel#section]]
        let regex = try? NSRegularExpression(
            pattern: "\\[\\[\(pattern)(?<suffix>[|#][^\\]]*)?\\]\\]",
            options: [.caseInsensitive]
        )
        guard let regex else { return 0 }

        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == "md" && url != skipping {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { continue }
            // Snapshot pre-rewrite.
            try? raw.write(to: url.appendingPathExtension("bak"),
                           atomically: true, encoding: .utf8)
            // Build replacement preserving any suffix (|alias / #section).
            var result = ""
            var lastEnd = 0
            for m in matches {
                let prior = ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
                result += prior
                let suffixRange = m.range(withName: "suffix")
                var suffix = ""
                if suffixRange.location != NSNotFound {
                    suffix = ns.substring(with: suffixRange)
                }
                result += "[[\(newLabel)\(suffix)]]"
                lastEnd = m.range.location + m.range.length
                totalReplacements += 1
            }
            result += ns.substring(from: lastEnd)
            try? result.write(to: url, atomically: true, encoding: .utf8)
        }
        return totalReplacements
    }

    /// Find clusters of nodes whose normalized slugs match. Used by the
    /// duplicate-detection banner on vault load. Each cluster contains
    /// two or more node ids.
    ///
    /// We bucket by id-normalized form only (e.g. "Usenet job posting"
    /// and "usenet-job-posting" share a key). Earlier versions also
    /// bucketed by label-normalized form, but that produced false
    /// positives for *legitimately distinct* same-label nodes — GEXF
    /// imports that contain, e.g., a "Star Trek (franchise)" node and
    /// a "Star Trek (1979 film)" node end up as `star-trek.md` and
    /// `star-trek-2.md` (id-distinct), both with the heading "Star
    /// Trek". Those shouldn't be flagged for review.
    func duplicateClusters() -> [[String]] {
        var buckets: [String: [String]] = [:]
        for (id, _) in graph.nodes {
            let key = Self.normalizedSlug(id)
            buckets[key, default: []].append(id)
        }
        return buckets.values
            .map { Array(Set($0)) }
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
    }

    /// Resolve `target` (a label or slug) to a node id (case-insensitive)
    /// and add an edge from `sourceID` to it if one doesn't already
    /// exist. No-op when the target doesn't resolve.
    private func wireEdge(from sourceID: String, to target: String, relationshipType: String?) {
        let needle = target.lowercased()
        let targetID = graph.nodes.keys.first { $0.lowercased() == needle }
            ?? graph.nodes.values.first { $0.label.lowercased() == needle }?.id
        guard let tid = targetID, tid != sourceID else { return }
        let edgeID = "\(sourceID)->\(tid)\(relationshipType.map { "::\($0)" } ?? "")"
        if graph.edges.contains(where: { $0.id == edgeID }) { return }
        var edge = Edge(id: edgeID, sourceID: sourceID, targetID: tid)
        edge.relationshipType = relationshipType
        graph.edges.append(edge)
    }

    /// Materialize an already-parsed GEXF document as a vault at
    /// `destination`. The GEXF was parsed earlier (while the picker's
    /// security scope was alive) so we no longer need access to the
    /// source file. After write, the new vault is loaded as usual.
    func importGEXFDocument(_ document: GEXFImporter.Document, into destination: URL) {
        let didStart = destination.startAccessingSecurityScopedResource()
        Task {
            defer { if didStart { destination.stopAccessingSecurityScopedResource() } }
            do {
                let written = try GEXFImporter.writeVault(document, to: destination)
                loadStatus = "Imported \(written) nodes — loading vault…"
            } catch {
                loadStatus = "GEXF import failed: \(error.localizedDescription)"
                return
            }
            load(from: destination)
        }
    }

    /// Initialize an empty vault at `url` (creates folder + subfolders +
    /// stub README) and load it. Caller is responsible for having
    /// started the security scope on `url` if it came from a picker.
    func createNewVault(at url: URL, template: Template? = nil) {
        let didStart = url.startAccessingSecurityScopedResource()
        Task {
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                try VaultWriter.initializeEmptyVault(at: url, template: template)
            } catch {
                loadStatus = "Couldn't create vault: \(error.localizedDescription)"
                return
            }
            // Hand off to the normal load path so we pick up the new
            // empty graph + register the bookmark + library entry.
            // The template's mode + types are already in
            // `.terracognita/config.yaml`, so `load(from:)` reads them
            // through `VaultConfig.load` and the toolbar mode pill
            // updates automatically.
            load(from: url)
        }
    }

    private enum VaultError: Error { case notFound }

    /// Non-isolated worker — runs on a background thread when awaited.
    /// Returns (vault-name, graph, isWritable, vaultURL). The bundled
    /// Miyazaki demo is read-only; on-disk dev vaults are writable.
    /// Load a vault folder under an NSFileCoordinator read on iOS so
    /// `FileManager.enumerator` reliably sees the contents of
    /// Files-app / iCloud-Drive folders — the security-scoped
    /// bracket alone is not always enough for provider-backed URLs.
    /// macOS doesn't need the coordinator wrap, so we fall through
    /// directly there to avoid the extra ceremony.
    nonisolated private static func coordinatedLoad(at url: URL,
                                                    config: VaultConfig) throws -> (Graph, VaultLoader.Diagnostics) {
        #if canImport(UIKit)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var loadResult: (Graph, VaultLoader.Diagnostics)?
        var loadError: Error?
        coordinator.coordinate(readingItemAt: url,
                               options: [],
                               error: &coordError) { coordURL in
            do {
                loadResult = try VaultLoader(vaultURL: coordURL,
                                             config: config).load()
            } catch {
                loadError = error
            }
        }
        if let err = coordError { throw err }
        if let err = loadError { throw err }
        if let result = loadResult { return result }
        return (Graph(nodes: [:], edges: []), VaultLoader.Diagnostics())
        #else
        return try VaultLoader(vaultURL: url, config: config).load()
        #endif
    }

    private static func loadFromDefaultVault() async throws -> (String, Graph, Bool, URL) {
        guard let vaultURL = VaultLoader.defaultVault() else {
            throw VaultError.notFound
        }
        let cfg = VaultConfig.load(from: vaultURL)
        let loader = VaultLoader(vaultURL: vaultURL, config: cfg)
        let (g, _) = try loader.load()
        // Bundle resources live under .../Resources/ inside the app
        // bundle and aren't writable. Anything else we resolved (the
        // dev heritage vault, etc.) is treated as writable.
        let isBundle = vaultURL.path.contains("/Resources/")
        return (vaultURL.lastPathComponent, g, !isBundle, vaultURL)
    }
}

// Lightweight graph model used by GraphStore.
// Matches usage in GraphCanvasView: `graph.nodes.values` and `graph.edges`
// with `Edge.id`, `Edge.sourceID`, `Edge.targetID`, `Edge.provenance`.
struct Graph {
    var nodes: [String: Node]
    var edges: [Edge]
}

// NOTE: We assume `Node` and `Edge` are defined elsewhere in the project.
// If they are not, you can uncomment the placeholder definitions below to make the project compile,
// and then replace them with your real models when ready.

/*
struct Node: Identifiable, Hashable {
    var id: String
    var label: String
    var type: String
}

struct Edge: Identifiable, Hashable {
    var id: String
    var sourceID: String
    var targetID: String
    var provenance: Provenance?
}

enum Provenance: String, Codable, CaseIterable, Hashable {
    case directInfluence
    case verifiedLineage
    case institutionalConnection
    case inferredAffinity
    case recommendation
    case adjacency
    case speculation
}
*/
