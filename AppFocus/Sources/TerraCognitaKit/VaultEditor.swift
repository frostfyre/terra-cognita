import Foundation

/// File-level mutations on an existing vault note. Companion to
/// `VaultWriter` (which creates new notes); this one edits.
///
/// **Safety rail:** on the first edit per file per process, a `.bak`
/// snapshot is written next to the original so the user always has a
/// pre-AI copy to fall back on. Subsequent edits within the same session
/// reuse that snapshot (we don't keep rolling backups — git / Time
/// Machine cover deeper history).
struct VaultEditor {
    let vaultURL: URL

    enum EditError: LocalizedError {
        case fileMissing(String)
        case readFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileMissing(let p): return "Note file not found at \(p)."
            case .readFailed(let r):  return "Couldn't read note — \(r)"
            case .writeFailed(let r): return "Couldn't write note — \(r)"
            }
        }
    }

    /// Append a wikilink to the body of the note at `fileURL`. If
    /// `relationshipType` is non-nil, emits the Dataview form
    /// `key:: [[target]]`; otherwise a bare `[[target]]` on its own line.
    /// Returns the new full body so callers can update in-memory state.
    func appendLink(in fileURL: URL,
                    target: String,
                    relationshipType: String?) throws -> String {
        let raw = try readFile(fileURL)
        try snapshotIfNeeded(fileURL, original: raw)

        var body = raw
        // Ensure a trailing newline before our append.
        if !body.hasSuffix("\n") { body += "\n" }
        if !body.hasSuffix("\n\n") { body += "\n" }
        if let rel = relationshipType, !rel.isEmpty {
            body += "\(rel):: [[\(target)]]\n"
        } else {
            body += "[[\(target)]]\n"
        }
        try writeFile(fileURL, contents: body)
        return body
    }

    /// Set (or insert) a single YAML front-matter key. Adds a
    /// front-matter block if the note didn't have one.
    func setFrontMatter(in fileURL: URL,
                        key: String,
                        value: String) throws -> String {
        let raw = try readFile(fileURL)
        try snapshotIfNeeded(fileURL, original: raw)

        let updated = Self.upsertFrontMatter(in: raw, key: key, value: value)
        try writeFile(fileURL, contents: updated)
        return updated
    }

    /// Replace the body (everything after the front-matter block) with
    /// `newBody`. Preserves the existing front-matter so types and
    /// metadata don't get clobbered.
    func replaceBody(in fileURL: URL,
                     newBody: String) throws -> String {
        let raw = try readFile(fileURL)
        try snapshotIfNeeded(fileURL, original: raw)

        let (frontMatter, _) = Self.splitFrontMatter(raw)
        var combined = ""
        if let fm = frontMatter, !fm.isEmpty {
            combined += "---\n\(fm)\n---\n\n"
        }
        combined += newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.hasSuffix("\n") { combined += "\n" }
        try writeFile(fileURL, contents: combined)
        return combined
    }

    // MARK: - .bak snapshot bookkeeping

    /// In-process registry of files we've already snapshotted this
    /// session. Single source of truth — VaultEditor is a value type
    /// but the actor-isolated static lock keeps mutations safe.
    private static let snapshotLock = NSLock()
    nonisolated(unsafe) private static var snapshotted: Set<String> = []

    private func snapshotIfNeeded(_ fileURL: URL, original raw: String) throws {
        let key = fileURL.path
        Self.snapshotLock.lock()
        let already = Self.snapshotted.contains(key)
        if !already { Self.snapshotted.insert(key) }
        Self.snapshotLock.unlock()
        if already { return }
        let bak = fileURL.appendingPathExtension("bak")
        do {
            try raw.write(to: bak, atomically: true, encoding: .utf8)
        } catch {
            // Snapshot failure is logged but doesn't block the edit —
            // git / Time Machine remain the deeper backstop.
            print("VaultEditor: failed to snapshot \(bak.path): \(error)")
        }
    }

    // MARK: - Low-level file I/O

    private func readFile(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EditError.fileMissing(url.path)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw EditError.readFailed(error.localizedDescription)
        }
    }

    private func writeFile(_ url: URL, contents: String) throws {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw EditError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - YAML helpers

    /// Splits `raw` into (front-matter-content, body). `nil` front
    /// matter means the file didn't have a `---` block at the top.
    static func splitFrontMatter(_ raw: String) -> (String?, String) {
        guard raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") else {
            return (nil, raw)
        }
        let afterFirst = raw.dropFirst(raw.hasPrefix("---\r\n") ? 5 : 4)
        guard let endRange = afterFirst.range(of: "\n---") else {
            return (nil, raw)
        }
        let fm = String(afterFirst[..<endRange.lowerBound])
        var rest = String(afterFirst[endRange.upperBound...])
        // Eat the newline(s) right after the closing fence.
        if rest.hasPrefix("\n")   { rest.removeFirst() }
        if rest.hasPrefix("\r\n") { rest.removeFirst(2) }
        return (fm, rest)
    }

    /// Upsert a YAML key into the front-matter block of `raw`. If the
    /// block doesn't exist, one is added.
    static func upsertFrontMatter(in raw: String, key: String, value: String) -> String {
        let (fmContent, body) = splitFrontMatter(raw)
        var lines: [String] = fmContent.map {
            $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } ?? []

        var replaced = false
        let prefix = "\(key):"
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                lines[i] = "\(key): \(value)"
                replaced = true
                break
            }
        }
        if !replaced {
            lines.append("\(key): \(value)")
        }
        let newFM = lines.joined(separator: "\n")
        return "---\n\(newFM)\n---\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
