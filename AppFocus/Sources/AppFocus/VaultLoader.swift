import Foundation

/// Builds a `Graph` (nodes + edges) from an Obsidian-style markdown vault.
///
/// Per DESIGN.md: "Markdown files remain the canonical backing store, while
/// the graph becomes the primary interaction model." Each `.md` file becomes
/// a node; YAML front-matter becomes node attributes; `[[wikilinks]]` in the
/// body become edges. Inline Dataview-style `key:: [[target]]` lines become
/// typed edges (the `key` is stored as `relationshipType`).
struct VaultLoader {
    let vaultURL: URL

    /// Resolves a vault directory by trying, in order:
    ///   1. The Miyazaki demo vault bundled with AppFocusKit (`Bundle.module`)
    ///   2. The current working directory + `Data/heritage-vault/heritage-vault`
    ///      (where the development heritage vault lives on macOS via swift run)
    ///   3. The executable's parent chain (walks up 8 levels)
    static func defaultVault() -> URL? {
        let fm = FileManager.default

        // 1. Library-bundled Miyazaki demo vault. Always present on iOS
        //    and any Xcode app target; first preference everywhere.
        if let bundled = Bundle.module.url(forResource: "miyazaki-vault",
                                           withExtension: nil) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: bundled.path, isDirectory: &isDir),
               isDir.boolValue {
                return bundled
            }
        }

        // 2. Filesystem fallback for development (swift run, working dir at repo root).
        let needle = "Data/heritage-vault/heritage-vault"
        var candidates: [URL] = []
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath))
        var dir = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        for _ in 0..<8 {
            candidates.append(dir)
            dir = dir.deletingLastPathComponent()
        }
        for base in candidates {
            let url = base.appendingPathComponent(needle)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }

    /// Loads the entire vault into a `Graph`. Edges are only added when both
    /// endpoints resolve to a known node, so dangling wikilinks are dropped.
    func load() throws -> Graph {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return Graph(nodes: [:], edges: [])
        }

        var nodes: [String: Node] = [:]
        // (sourceID, targetSlug, relationshipType?) — resolved in a second pass.
        var pendingEdges: [(String, String, String?)] = []

        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == "md" {
            let id = url.deletingPathExtension().lastPathComponent
            // Skip README and top-level vault docs.
            if id.uppercased() == "README" { continue }

            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let parsed = MarkdownNoteParser.parse(raw)

            var attributes = parsed.frontMatter
            attributes["folder"] = url.deletingLastPathComponent().lastPathComponent
            // Default a "type" if front-matter didn't supply one — derived
            // from the containing folder (concepts → concept, etc.).
            if attributes["type"] == nil {
                let folder = attributes["folder"] ?? ""
                if folder.hasSuffix("s") {
                    attributes["type"] = String(folder.dropLast())
                }
            }

            var node = Node(id: id, label: parsed.title ?? id)
            node.attributes = attributes
            node.filePath = url.path
            node.markdownContent = parsed.body
            nodes[id] = node

            for link in parsed.links {
                pendingEdges.append((id, link.target, link.relationshipType))
            }
        }

        // Resolve wikilinks to known nodes. Wikilinks point at filenames
        // (case-insensitively); build a slug index that handles both forms.
        var slugIndex: [String: String] = [:]
        for id in nodes.keys {
            slugIndex[id.lowercased()] = id
        }

        var edges: [Edge] = []
        var seen: Set<String> = []
        for (sourceID, targetSlug, kind) in pendingEdges {
            guard let targetID = slugIndex[targetSlug.lowercased()] else { continue }
            if targetID == sourceID { continue }
            let edgeID = "\(sourceID)->\(targetID)\(kind.map { "::\($0)" } ?? "")"
            if seen.contains(edgeID) { continue }
            seen.insert(edgeID)

            var edge = Edge(id: edgeID, sourceID: sourceID, targetID: targetID)
            edge.relationshipType = kind
            edges.append(edge)
        }

        return Graph(nodes: nodes, edges: edges)
    }
}

// MARK: - Markdown note parsing

/// Lightweight parser for the vault's note format: YAML front-matter,
/// a `# Heading`, body text, and Obsidian/Dataview wikilinks.
enum MarkdownNoteParser {
    struct Parsed {
        var frontMatter: [String: String] = [:]
        var title: String?
        var body: String = ""
        var links: [Link] = []
    }

    struct Link {
        let target: String          // The file slug (before `|`, before `#`)
        let relationshipType: String?  // The key of a `key:: [[target]]` line, if any
    }

    static func parse(_ raw: String) -> Parsed {
        var result = Parsed()
        var body = raw

        // --- Front matter ---
        if body.hasPrefix("---\n") || body.hasPrefix("---\r\n") {
            let afterFirstFence = body.dropFirst(body.hasPrefix("---\r\n") ? 5 : 4)
            if let endRange = afterFirstFence.range(of: "\n---") {
                let frontText = afterFirstFence[..<endRange.lowerBound]
                result.frontMatter = parseFrontMatter(String(frontText))
                let afterFenceIndex = afterFirstFence.index(endRange.upperBound, offsetBy: 0)
                var rest = String(afterFirstFence[afterFenceIndex...])
                if rest.hasPrefix("\n") { rest.removeFirst() }
                if rest.hasPrefix("\r\n") { rest.removeFirst(2) }
                body = rest
            }
        }

        // --- Title from first `# Heading` ---
        for line in body.split(separator: "\n", maxSplits: 8, omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                result.title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        result.body = body
        result.links = extractLinks(body)
        return result
    }

    /// Extracts every `[[wikilink]]` from the text. Lines that look like
    /// `key:: [[target]]` produce links tagged with `relationshipType = key`.
    static func extractLinks(_ text: String) -> [Link] {
        var links: [Link] = []
        let linkPattern = #"\[\[([^\]\n|#]+)(?:[#|][^\]\n]*)?\]\]"#
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern) else { return [] }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            // Detect Dataview `key:: ...` lines (key is leading bareword before `::`).
            var relType: String?
            if let dvRange = line.range(of: "::") {
                let prefix = line[..<dvRange.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty,
                   prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                    relType = prefix
                }
            }

            let matches = linkRegex.matches(in: line, range: fullRange)
            for m in matches where m.numberOfRanges >= 2 {
                let target = nsLine.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                if target.isEmpty { continue }
                links.append(Link(target: target, relationshipType: relType))
            }
        }
        return links
    }

    /// Minimal YAML front-matter: `key: value` and `key: [a, b]` styles.
    /// Values are stored as strings; arrays are joined with `, `.
    static func parseFrontMatter(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") && value.hasSuffix("]") {
                value = String(value.dropFirst().dropLast())
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: ", ")
            }
            if !key.isEmpty { out[key] = value }
        }
        return out
    }
}
