import Foundation

/// GEXF (Graph Exchange XML Format) importer. Reads a `.gexf` file and
/// materializes a Terra Cognita atlas from it — one `.md` per node with
/// the node's attributes folded into YAML front-matter and any
/// description becoming the body. Edges are emitted as Dataview-style
/// `relation:: [[target]]` lines on the source node so the standard
/// atlas loader picks them up.
///
/// Goal: GEXF is a one-shot import, not a live format. After the
/// import the atlas is just markdown — every other Terra Cognita
/// affordance (AI ops, ingestion, dive-in, etc.) works as usual.
struct GEXFImporter {

    // MARK: - Parsed in-memory shape

    struct Document {
        struct AttributeDecl {
            let id: String
            let title: String
        }
        struct NodeRecord {
            let id: String
            let label: String
            /// title → value (titles are the human-readable names from
            /// the `<attributes>` decls; the GEXF `<attvalue>` rows
            /// reference attributes by id and we resolve them here).
            var values: [String: String]
        }
        struct EdgeRecord {
            let source: String
            let target: String
            var values: [String: String]
        }
        var nodeAttributes: [AttributeDecl] = []
        var edgeAttributes: [AttributeDecl] = []
        var nodes: [NodeRecord] = []
        var edges: [EdgeRecord] = []
    }

    enum ImportError: LocalizedError {
        case parseFailed(String)
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .parseFailed(let s): return "Couldn't parse GEXF — \(s)"
            case .writeFailed(let s): return "Couldn't write atlas — \(s)"
            }
        }
    }

    // MARK: - Public entry points

    /// Parse a `.gexf` file from disk into the in-memory document shape.
    static func parse(fileURL: URL) throws -> Document {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ImportError.parseFailed("couldn't read \(fileURL.lastPathComponent)")
        }
        let parser = XMLParser(data: data)
        let delegate = GEXFParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            let err = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw ImportError.parseFailed(err)
        }
        return delegate.document
    }

    /// Materialize `document` as a Terra Cognita atlas under `destination`.
    /// Creates the destination folder (if needed) and writes one `.md`
    /// per node. Returns the number of nodes written.
    @discardableResult
    static func writeAtlas(_ document: Document, to destination: URL) throws -> Int {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        // Pre-index edges so each node can list its outbound relations
        // inline (Dataview style) — the atlas loader picks these up.
        var edgesBySource: [String: [Document.EdgeRecord]] = [:]
        for edge in document.edges {
            edgesBySource[edge.source, default: []].append(edge)
        }
        // node id → label, so the relation lines can use the human-
        // readable name in the wikilink target.
        var labelByID: [String: String] = [:]
        for node in document.nodes {
            labelByID[node.id] = node.label
        }

        var written = 0
        var usedFilenames: Set<String> = []

        // Seed `usedFilenames` with any `.md` slugs already present at
        // the destination so a re-import doesn't silently overwrite the
        // existing atlas. Walk the top-level folder plus the recognised
        // subfolders (concepts/, events/, …) since that's where the
        // importer writes.
        let existingSlugs = collectExistingSlugs(under: destination)
        usedFilenames.formUnion(existingSlugs)

        for node in document.nodes {
            // Build the slug: based on label, filesystem-safe, unique.
            let baseSlug = AtlasWriter.makeSlug(from: node.label.isEmpty ? node.id : node.label)
            var slug = baseSlug
            var n = 2
            while usedFilenames.contains(slug.lowercased()) {
                slug = "\(baseSlug) \(n)"
                n += 1
            }
            usedFilenames.insert(slug.lowercased())

            // Decide where it lives — by GEXF "type" if we recognise it.
            let typeRaw = node.values["type"]?.lowercased()
            let subfolder = typeRaw.flatMap { AtlasWriter.subfolder(for: $0) }
            let folderURL = subfolder.map {
                destination.appendingPathComponent($0)
            } ?? destination
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let fileURL = folderURL.appendingPathComponent("\(slug).md")
            let body = renderNote(node: node,
                                  outbound: edgesBySource[node.id] ?? [],
                                  labelByID: labelByID)
            do {
                try body.write(to: fileURL, atomically: true, encoding: .utf8)
                written += 1
            } catch {
                throw ImportError.writeFailed(error.localizedDescription)
            }
        }
        return written
    }

    /// Collect lowercased slugs (filenames without `.md`) already
    /// present at `destination` or any of its first-level subfolders.
    /// Used to make re-imports additive instead of destructive.
    private static func collectExistingSlugs(under destination: URL) -> Set<String> {
        let fm = FileManager.default
        var slugs: Set<String> = []
        guard let topLevel = try? fm.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return slugs }

        for url in topLevel {
            if url.pathExtension.lowercased() == "md" {
                slugs.insert(url.deletingPathExtension().lastPathComponent.lowercased())
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let children = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) {
                    for child in children where child.pathExtension.lowercased() == "md" {
                        slugs.insert(child.deletingPathExtension().lastPathComponent.lowercased())
                    }
                }
            }
        }
        return slugs
    }

    // MARK: - Note rendering

    /// Attribute names that — if present — are treated as primary
    /// body prose rather than frontmatter metadata. They get
    /// appended without a heading. Anything else that looks prose-y
    /// (long value, or value with newlines) gets a `## Key` heading
    /// so the user can still tell the sections apart.
    private static let proseAttributeNames: Set<String> = [
        "description", "body", "content", "summary",
        "bio", "notes", "text", "prose", "abstract",
        "overview", "background", "story",
    ]

    /// Threshold above which an unlabeled attribute is treated as
    /// prose (and lands in the body) rather than frontmatter. 80
    /// chars is roughly the boundary between "tag-like" and "sentence".
    private static let proseLengthThreshold = 80

    private static func renderNote(node: Document.NodeRecord,
                                   outbound: [Document.EdgeRecord],
                                   labelByID: [String: String]) -> String {
        var lines: [String] = []

        // Partition node.values into frontmatter-eligible (short
        // scalars) and prose-eligible (long, multi-line, or a
        // recognized prose attribute name). This keeps multi-line
        // descriptions out of YAML (where they break parsing) and
        // preserves them in the body where they can render.
        var frontmatterEntries: [(String, String)] = []
        var proseEntries: [(String, String)] = []
        for (k, v) in node.values where !v.isEmpty {
            let key = k.lowercased()
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            let isMultiLine = v.contains("\n") || v.contains("\r")
            let isLong = trimmed.count > proseLengthThreshold
            let isPrimaryProse = proseAttributeNames.contains(key)
            if isPrimaryProse || isMultiLine || isLong {
                proseEntries.append((key, v))
            } else {
                let value = key == "type" ? v.lowercased() : v
                frontmatterEntries.append((key, value))
            }
        }
        // Stash the original GEXF id so re-imports can be deduped later.
        frontmatterEntries.append(("gexf-id", node.id))
        frontmatterEntries.sort { $0.0 < $1.0 }

        if !frontmatterEntries.isEmpty {
            lines.append("---")
            for (k, v) in frontmatterEntries {
                lines.append("\(k): \(yamlEscape(v))")
            }
            lines.append("---")
            lines.append("")
        }

        lines.append("# \(node.label.isEmpty ? node.id : node.label)")
        lines.append("")

        // Prose body — every long / multi-line / named-prose
        // attribute, in a stable order. Primary prose names
        // (description, summary, body, etc.) render headless;
        // other prose attributes get a `## Key` heading so the
        // user can tell sections apart.
        let proseOrder: (String, String) -> Bool = { a, b in
            // Primary prose first, alphabetical within each tier.
            let aPrimary = proseAttributeNames.contains(a)
            let bPrimary = proseAttributeNames.contains(b)
            if aPrimary != bPrimary { return aPrimary }
            return a < b
        }
        let sortedProse = proseEntries.sorted { proseOrder($0.0, $1.0) }
        for (k, v) in sortedProse {
            if !proseAttributeNames.contains(k) {
                lines.append("## \(k.capitalized)")
                lines.append("")
            }
            lines.append(v)
            lines.append("")
        }

        // Outbound relations — Dataview style so the atlas loader
        // creates typed edges with the GEXF relation as the type.
        if !outbound.isEmpty {
            for edge in outbound {
                let relation = edge.values["relation"]?.replacingOccurrences(of: " ", with: "-")
                    ?? "relates-to"
                guard let targetLabel = labelByID[edge.target] else { continue }
                lines.append("\(relation):: [[\(targetLabel)]]")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func yamlEscape(_ raw: String) -> String {
        // Wrap values that contain colons / hashes / quotes in double
        // quotes so the YAML parser reads them correctly. Inner quotes
        // get backslash-escaped.
        let needsQuoting = raw.contains(":") || raw.contains("#") ||
                           raw.contains("\"") || raw.hasPrefix(" ") ||
                           raw.hasSuffix(" ") || raw.isEmpty
        if !needsQuoting { return raw }
        let escaped = raw.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - SAX delegate

private final class GEXFParserDelegate: NSObject, XMLParserDelegate {
    private(set) var document = GEXFImporter.Document()

    // Active state during streaming parse.
    private enum AttrClass { case node, edge, other }
    private var currentAttrClass: AttrClass = .other
    private var currentNode: GEXFImporter.Document.NodeRecord?
    private var currentEdge: GEXFImporter.Document.EdgeRecord?
    /// (id, title) for attribute decls in this <attributes> block.
    private var pendingAttributeIDs: [String: String] = [:]
    private var attributeIDToTitle: [String: String] = [:]
    /// Buffer for `<attvalue for="N" value="V"/>` rows whose enclosing
    /// element will receive them on `didEndElement`.
    private var pendingAttValues: [String: String] = [:]

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "attributes":
            switch attributeDict["class"] {
            case "node": currentAttrClass = .node
            case "edge": currentAttrClass = .edge
            default:     currentAttrClass = .other
            }
            pendingAttributeIDs.removeAll()

        case "attribute":
            if let id = attributeDict["id"], let title = attributeDict["title"] {
                pendingAttributeIDs[id] = title
                attributeIDToTitle[id] = title
                let decl = GEXFImporter.Document.AttributeDecl(id: id, title: title)
                switch currentAttrClass {
                case .node: document.nodeAttributes.append(decl)
                case .edge: document.edgeAttributes.append(decl)
                case .other: break
                }
            }

        case "node":
            currentNode = .init(
                id: attributeDict["id"] ?? UUID().uuidString,
                label: attributeDict["label"] ?? "",
                values: [:]
            )
            pendingAttValues.removeAll()

        case "edge":
            let source = attributeDict["source"] ?? ""
            let target = attributeDict["target"] ?? ""
            currentEdge = .init(source: source, target: target, values: [:])
            pendingAttValues.removeAll()

        case "attvalue":
            if let forID = attributeDict["for"],
               let value = attributeDict["value"],
               let title = attributeIDToTitle[forID] {
                pendingAttValues[title] = value
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "node":
            if var node = currentNode {
                node.values = pendingAttValues
                document.nodes.append(node)
            }
            currentNode = nil
            pendingAttValues.removeAll()

        case "edge":
            if var edge = currentEdge {
                edge.values = pendingAttValues
                document.edges.append(edge)
            }
            currentEdge = nil
            pendingAttValues.removeAll()

        case "attributes":
            currentAttrClass = .other

        default:
            break
        }
    }
}
