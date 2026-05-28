import Foundation

/// Writes new node files into a markdown atlas, matching the format
/// `AtlasLoader` expects: YAML front-matter, `# Title`, then body. New
/// nodes are placed into the type-conventional subfolder (`people/`,
/// `concepts/`, …) and given a filesystem-safe filename derived from the
/// label, with collision avoidance via numeric suffix.
struct AtlasWriter {
    let atlasURL: URL

    enum WriteError: LocalizedError {
        case emptyLabel
        case atlasUnwritable(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyLabel:                 return "Label can't be empty."
            case .atlasUnwritable(let why):   return "Atlas isn't writable — \(why)"
            case .writeFailed(let why):       return "Write failed — \(why)"
            }
        }
    }

    /// Write a new node into the atlas. Returns the URL of the created
    /// file plus the slug that will become the node's id. Assumes the
    /// caller has already started the security-scoped resource if needed.
    func createNote(label: String,
                    type: String?,
                    era: String?,
                    body: String,
                    isPrivate: Bool = false) throws -> (fileURL: URL, slug: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { throw WriteError.emptyLabel }

        let fm = FileManager.default
        let folderURL = subfolderURL(for: type, base: atlasURL)
        do {
            try fm.createDirectory(at: folderURL,
                                   withIntermediateDirectories: true)
        } catch {
            throw WriteError.atlasUnwritable("couldn't create \(folderURL.path) (\(error.localizedDescription))")
        }

        let baseSlug = Self.makeSlug(from: trimmedLabel)
        let slug = uniqueSlug(baseSlug, in: folderURL)
        let fileURL = folderURL.appendingPathComponent("\(slug).md")

        let contents = renderNote(label: trimmedLabel, type: type, era: era,
                                  body: body, isPrivate: isPrivate)
        do {
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw WriteError.writeFailed(error.localizedDescription)
        }
        return (fileURL, slug)
    }

    // MARK: - Atlas creation

    /// Initialize an empty atlas in `url`. When a `template` is given,
    /// uses its mode + types + eras to (a) materialize the appropriate
    /// subfolders, and (b) write `.terracognita/config.yaml` so the
    /// atlas loads with the template's ontology on first open. When
    /// `template` is nil the historical behavior is preserved —
    /// hardcoded Continuity subfolders, no config file.
    /// Idempotent — existing folders/files are left alone.
    static func initializeEmptyAtlas(at url: URL,
                                     template: Template? = nil) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        let subfolders = template?.subfolders
            ?? ["people", "concepts", "institutions", "events", "works"]
        for sub in subfolders {
            try fm.createDirectory(at: url.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }
        let readme = url.appendingPathComponent("README.md")
        if !fm.fileExists(atPath: readme.path) {
            let modeLabel = template?.mode.displayName ?? "Continuity"
            let templateLabel = template?.name ?? "default"
            let body = """
            # \(url.lastPathComponent)

            Terra Cognita atlas — \(modeLabel) mode, \(templateLabel) template.
            Each `.md` file in a typed subfolder is a node; `[[wikilinks]]`
            in note bodies become edges.
            """
            try? body.write(to: readme, atomically: true, encoding: .utf8)
        }
        // Materialize `.terracognita/config.yaml` only when a template
        // is provided. Untagged atlases stay backward-compatible: no
        // config file means `AtlasConfig.default` (Continuity) on load.
        if let template {
            let config = AtlasConfig(
                mode: template.mode,
                types: template.types,
                eras: template.eras.isEmpty
                    ? AtlasConfig.default.eras
                    : template.eras,
                extractors: AtlasConfig.Extractors()
            )
            try? config.save(to: url)
        }
    }

    // MARK: - Helpers

    private func renderNote(label: String,
                            type: String?,
                            era: String?,
                            body: String,
                            isPrivate: Bool) -> String {
        var fm: [String] = []
        if let type, !type.isEmpty { fm.append("type: \(type)") }
        if let era, !era.isEmpty   { fm.append("era: \(era)") }
        if isPrivate               { fm.append("private: true") }

        var out = ""
        if !fm.isEmpty {
            out += "---\n"
            out += fm.joined(separator: "\n")
            out += "\n---\n\n"
        }
        out += "# \(label)\n\n"
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            out += trimmedBody
            out += "\n"
        }
        return out
    }

    private func subfolderURL(for type: String?, base: URL) -> URL {
        guard let type, let sub = Self.subfolder(for: type) else { return base }
        return base.appendingPathComponent(sub)
    }

    static func subfolder(for type: String) -> String? {
        switch type.lowercased() {
        case "person":      return "people"
        case "concept":     return "concepts"
        case "institution": return "institutions"
        case "event":       return "events"
        case "work":        return "works"
        default:            return nil
        }
    }

    /// Sanitize a label for use as a filename. Preserves spaces (the
    /// atlas format is fine with them) but strips filesystem-hostile
    /// characters.
    static func makeSlug(from label: String) -> String {
        let stripped = label.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "/", "\\", ":", "?", "*", "<", ">", "|", "\"":
                return "-"
            default:
                return Character(scalar)
            }
        }
        var slug = String(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse runs of whitespace to a single space.
        while slug.contains("  ") { slug = slug.replacingOccurrences(of: "  ", with: " ") }
        return slug.isEmpty ? "Untitled" : slug
    }

    private func uniqueSlug(_ base: String, in folder: URL) -> String {
        let fm = FileManager.default
        var candidate = base
        var n = 2
        while fm.fileExists(atPath: folder.appendingPathComponent("\(candidate).md").path) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return candidate
    }
}
