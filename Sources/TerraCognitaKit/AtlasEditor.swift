import Foundation

/// File-level mutations on an existing atlas note. Companion to
/// `AtlasWriter` (which creates new notes); this one edits.
///
/// **Safety rail:** on the first edit per file per process, a `.bak`
/// snapshot is written next to the original so the user always has a
/// pre-AI copy to fall back on. Subsequent edits within the same session
/// reuse that snapshot (we don't keep rolling backups — git / Time
/// Machine cover deeper history).
struct AtlasEditor {
    let atlasURL: URL
    /// Tracker for "first edit per file in this session" so we only
    /// write one `.bak` snapshot per file even across many mutations.
    /// `nil` means "snapshot every edit" — the conservative default
    /// when no owner has been provided (e.g. one-off test instances).
    var snapshots: SnapshotTracker?

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

    /// Rewrite the relationship type on an edge line. The line must
    /// be a *bare* edge declaration — optional `rel:: ` prefix, then
    /// `[[target]]` (optionally with `|alias`) on a line by itself.
    /// We refuse edges embedded mid-prose to avoid corrupting body
    /// text; callers should fall back to "edit the source note".
    ///
    /// `newRelationship == nil` removes the prefix entirely (the
    /// edge becomes a bare wikilink). Returns the updated body.
    func updateEdgeRelationship(in fileURL: URL,
                                target: String,
                                oldRelationship: String?,
                                newRelationship: String?) throws -> String {
        let raw = try readFile(fileURL)
        try snapshotIfNeeded(fileURL, original: raw)
        guard let updated = Self.rewriteEdgeLine(in: raw,
                                                 target: target,
                                                 oldRelationship: oldRelationship,
                                                 newRelationship: newRelationship,
                                                 removeLine: false) else {
            throw EditError.writeFailed("No editable edge line for [[\(target)]] — it may be embedded in prose.")
        }
        try writeFile(fileURL, contents: updated)
        return updated
    }

    /// Delete an edge by removing the entire line containing it.
    /// Same restrictions as `updateEdgeRelationship` — only bare
    /// edge lines are editable. Returns the updated body.
    func removeEdge(in fileURL: URL,
                    target: String,
                    relationshipType: String?) throws -> String {
        let raw = try readFile(fileURL)
        try snapshotIfNeeded(fileURL, original: raw)
        guard let updated = Self.rewriteEdgeLine(in: raw,
                                                 target: target,
                                                 oldRelationship: relationshipType,
                                                 newRelationship: nil,
                                                 removeLine: true) else {
            throw EditError.writeFailed("No editable edge line for [[\(target)]] — it may be embedded in prose.")
        }
        try writeFile(fileURL, contents: updated)
        return updated
    }

    /// Locate-and-rewrite a single edge line. Returns `nil` if no
    /// bare edge line matched — keeps prose-embedded wikilinks
    /// untouched. Matching is case-insensitive on `target` and
    /// trims whitespace around `[[…]]`.
    static func rewriteEdgeLine(in raw: String,
                                target: String,
                                oldRelationship: String?,
                                newRelationship: String?,
                                removeLine: Bool) -> String? {
        let needle = target.lowercased()
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard let parsed = Self.parseEdgeLine(trimmed) else { continue }
            if parsed.target.lowercased() != needle { continue }
            // Optional disambiguation: when caller passes the old
            // relationship type, require it to match — otherwise
            // multiple edges A → B with different types would
            // collide.
            if let oldRel = oldRelationship {
                if parsed.relationship?.lowercased() != oldRel.lowercased() { continue }
            } else if parsed.relationship != nil {
                // Caller meant "bare wikilink"; skip Dataview lines.
                continue
            }
            if removeLine {
                lines.remove(at: i)
            } else {
                let aliasSuffix = parsed.alias.map { "|\($0)" } ?? ""
                let link = "[[\(parsed.target)\(aliasSuffix)]]"
                if let newRel = newRelationship, !newRel.isEmpty {
                    lines[i] = "\(newRel):: \(link)"
                } else {
                    lines[i] = link
                }
            }
            return lines.joined(separator: "\n")
        }
        return nil
    }

    /// Parses a single trimmed line as an edge declaration. Returns
    /// `nil` if the line isn't *exclusively* a wikilink (optionally
    /// preceded by a Dataview `key::` prefix).
    static func parseEdgeLine(_ line: String) -> (relationship: String?, target: String, alias: String?)? {
        var work = line
        var relationship: String?
        if let dataviewSep = work.range(of: "::") {
            let key = work[..<dataviewSep.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            // Reject keys with whitespace or punctuation that wouldn't be a
            // valid Dataview attribute — this guards against prose like
            // "she said:: ..." being mistaken for an edge.
            let keyChars = CharacterSet(charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
            guard !key.isEmpty,
                  key.unicodeScalars.allSatisfy(keyChars.contains) else {
                return nil
            }
            relationship = key
            work = String(work[dataviewSep.upperBound...])
                .trimmingCharacters(in: .whitespaces)
        }
        guard work.hasPrefix("[["), work.hasSuffix("]]") else { return nil }
        let inner = work.dropFirst(2).dropLast(2)
        if inner.contains("[[") || inner.contains("]]") { return nil }
        // `"[[]]"` yields an empty `inner`; `split` returns an empty
        // array, so guard against that before indexing.
        if inner.isEmpty { return nil }
        let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return nil }
        let target = first.trimmingCharacters(in: .whitespaces)
        let alias = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : nil
        if target.isEmpty { return nil }
        return (relationship, target, alias)
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

    private func snapshotIfNeeded(_ fileURL: URL, original raw: String) throws {
        let shouldSnapshot: Bool = {
            guard let tracker = snapshots else { return true }
            return tracker.markFirstEdit(of: fileURL.path)
        }()
        guard shouldSnapshot else { return }
        let bak = fileURL.appendingPathExtension("bak")
        do {
            try raw.write(to: bak, atomically: true, encoding: .utf8)
        } catch {
            // Snapshot failure is logged but doesn't block the edit —
            // git / Time Machine remain the deeper backstop.
            print("AtlasEditor: failed to snapshot \(bak.path): \(error)")
        }
    }
}

extension AtlasEditor {

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
        // Defensive: ensure the parent directory exists before the
        // atomic write. The vast majority of "write failed — No such
        // file or directory" errors come from a missing parent — the
        // user reorganized in Finder, the type subfolder was deleted,
        // or the node's `filePath` predates a recent restructuring.
        // Creating the dir lazily means the write succeeds in all of
        // these instead of bouncing back as a hard error.
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent,
                                                 withIntermediateDirectories: true)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw EditError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - YAML helpers

    /// Splits `raw` into (front-matter-content, body). `nil` front
    /// matter means the file didn't have a `---` block at the top.
    ///
    /// Handles both LF and CRLF inputs. Swift treats `\r\n` as a
    /// single Character (extended grapheme cluster), which means
    /// `range(of: "\n---")` does **not** match a CRLF file — we
    /// search for both the LF form and the CRLF form explicitly.
    /// Returns the fm with trailing whitespace trimmed so downstream
    /// parsers don't have to deal with a stray `\r`.
    static func splitFrontMatter(_ raw: String) -> (String?, String) {
        guard raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") else {
            return (nil, raw)
        }
        // `\r\n` is a single extended grapheme cluster in Swift, so
        // both prefixes are 4 Characters long. dropFirst(4) is right
        // for both.
        let afterFirst = raw.dropFirst(4)
        // Try LF closing first, then CRLF closing. (We can't normalize
        // newlines up-front without changing what we write back.)
        let close: Range<Substring.Index>
        if let r = afterFirst.range(of: "\n---") {
            close = r
        } else if let r = afterFirst.range(of: "\r\n---") {
            close = r
        } else {
            return (nil, raw)
        }
        let fm = String(afterFirst[..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var rest = String(afterFirst[close.upperBound...])
        // Eat the newline(s) right after the closing fence.
        if rest.hasPrefix("\r\n") { rest.removeFirst(2) }
        else if rest.hasPrefix("\n") { rest.removeFirst() }
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

/// Reference-typed tracker for the "first edit per file this
/// session" rule. Lives on `GraphStore` so each store gets its own
/// scoped lifecycle (was a process-global `nonisolated(unsafe)
/// static` on AtlasEditor — moved here so tests + future
/// multi-atlas flows don't share state).
final class SnapshotTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<String> = []

    /// Returns `true` if this is the first time `path` is being
    /// reported; subsequent calls with the same path return `false`.
    /// Callers snapshot when `true`.
    func markFirstEdit(of path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let isFirst = !seen.contains(path)
        if isFirst { seen.insert(path) }
        return isFirst
    }
}
