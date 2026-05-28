import Foundation
import SwiftUI

/// Deterministic file-system → atlas executor for `ImportRecipe`.
/// Walks the source folder, materializes one `.md` per file matching
/// a `NodeRule.filePattern`, then applies `EdgeRule`s by writing
/// Dataview wikilinks into the appropriate node bodies. Writes a
/// `.terracognita/config.yaml` declaring the recipe's types so the
/// new atlas loads with the right palette.
///
/// "Deterministic" is the contract: the same source folder + recipe
/// always produces the same atlas. The interpreter is allowed to be
/// creative; the executor is not.
enum RecipeExecutor {

    enum ExecutorError: LocalizedError {
        case unreadableSource(String)
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .unreadableSource(let p): return "Couldn't read source folder \(p)."
            case .writeFailed(let r):      return "Couldn't write atlas — \(r)"
            }
        }
    }

    /// Result summary for the post-import banner. `nodesByType`
    /// keys the type name to its created count.
    struct Outcome {
        var nodesByType: [String: Int]
        var edgesCreated: Int
        var totalNodes: Int { nodesByType.values.reduce(0, +) }
    }

    /// Run a recipe. `source` is the folder the user pointed at;
    /// `destination` is where the new atlas lives. Caller is
    /// responsible for security-scoped access on both URLs.
    static func execute(_ recipe: ImportRecipe,
                        source: URL,
                        destination: URL) throws -> Outcome {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        // --- 1. Build the type vocabulary for the config + per-rule indexes.
        var typeSpecs: [AtlasConfig.TypeSpec] = []
        for rule in recipe.nodeRules {
            typeSpecs.append(.init(
                name: rule.typeName,
                displayName: nil,
                color: parseColor(rule.color),
                icon: "doc.fill",
                folder: rule.typeName
            ))
            try fm.createDirectory(
                at: destination.appendingPathComponent(rule.typeName),
                withIntermediateDirectories: true
            )
        }
        let config = AtlasConfig(
            mode: .projectArchaeology,
            types: typeSpecs,
            eras: [],
            extractors: AtlasConfig.Extractors()
        )
        try? config.save(to: destination)

        // --- 2. Walk the source folder, build per-rule file lists.
        let allFiles = try enumerate(source)
        var matchedByRule: [String: [URL]] = [:]   // rule.typeName → matched files
        var labelByFileURL: [URL: String] = [:]    // for edge name-reference lookups
        var typeByFileURL: [URL: String] = [:]
        var ruleByType: [String: ImportRecipe.NodeRule] = [:]
        for rule in recipe.nodeRules {
            ruleByType[rule.typeName] = rule
            matchedByRule[rule.typeName] = allFiles.filter { matches($0, pattern: rule.filePattern) }
        }

        // --- 3. Materialize one .md per matched source file.
        var nodesByType: [String: Int] = [:]
        for rule in recipe.nodeRules {
            let folder = destination.appendingPathComponent(rule.typeName)
            var written = 0
            for file in matchedByRule[rule.typeName] ?? [] {
                let label = labelFor(file, strategy: rule.labelStrategy)
                let slug = AtlasWriter.makeSlug(from: label)
                let target = folder.appendingPathComponent("\(slug).md")
                guard !fm.fileExists(atPath: target.path) else { continue }
                let body = """
                ---
                type: \(rule.typeName)
                source-file: \(file.path)
                ---

                # \(label)

                """
                do {
                    try body.write(to: target, atomically: true, encoding: .utf8)
                    written += 1
                    labelByFileURL[file] = label
                    typeByFileURL[file] = rule.typeName
                } catch {
                    throw ExecutorError.writeFailed(error.localizedDescription)
                }
            }
            nodesByType[rule.typeName] = written
        }

        // --- 4. Apply edge rules — append `relation:: [[target]]`
        // lines to the source-side node files.
        var edgesCreated = 0
        for edgeRule in recipe.edgeRules {
            let sources = matchedByRule[edgeRule.sourceType] ?? []
            let targets = matchedByRule[edgeRule.targetType] ?? []
            guard !sources.isEmpty, !targets.isEmpty,
                  let sourceTypeSubfolder = ruleByType[edgeRule.sourceType] else { continue }
            for src in sources {
                let srcLabel = labelByFileURL[src] ?? src.lastPathComponent
                let srcMD = destination
                    .appendingPathComponent(sourceTypeSubfolder.typeName)
                    .appendingPathComponent("\(AtlasWriter.makeSlug(from: srcLabel)).md")
                // Resolve candidate targets per strategy.
                let matchedTargets: [URL] = targets.filter { tgt in
                    matches(src, tgt, strategy: edgeRule.strategy, labels: labelByFileURL)
                }
                guard !matchedTargets.isEmpty,
                      var existing = try? String(contentsOf: srcMD, encoding: .utf8)
                else { continue }
                let relName = "\(edgeRule.targetType)-of"
                for tgt in matchedTargets {
                    let tgtLabel = labelByFileURL[tgt] ?? tgt.lastPathComponent
                    let line = "\(relName):: [[\(tgtLabel)]]\n"
                    if !existing.contains("[[\(tgtLabel)]]") {
                        if !existing.hasSuffix("\n") { existing += "\n" }
                        existing += line
                        edgesCreated += 1
                    }
                }
                try? existing.write(to: srcMD, atomically: true, encoding: .utf8)
            }
        }

        return Outcome(nodesByType: nodesByType, edgesCreated: edgesCreated)
    }

    // MARK: - File enumeration

    private static func enumerate(_ root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let it = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ExecutorError.unreadableSource(root.path)
        }
        var out: [URL] = []
        while let next = it.nextObject() as? URL {
            if let isFile = (try? next.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile),
               isFile == true {
                out.append(next)
            }
        }
        return out
    }

    // MARK: - Pattern + edge matching

    /// Minimal glob matcher — supports `*.ext` and `*` as a wildcard
    /// over any single segment. Good enough for the patterns the
    /// interpreter typically produces.
    private static func matches(_ url: URL, pattern raw: String) -> Bool {
        let pattern = raw.lowercased()
        let name = url.lastPathComponent.lowercased()
        if pattern == "*" { return true }
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return name.hasSuffix(".\(ext)")
        }
        if pattern.contains("*") {
            // Naive split-then-match-each-part scheme.
            let parts = pattern.split(separator: "*", omittingEmptySubsequences: false)
                .map { String($0) }
            var cursor = name.startIndex
            for (i, part) in parts.enumerated() where !part.isEmpty {
                guard let range = name.range(of: part, range: cursor..<name.endIndex) else {
                    return false
                }
                if i == 0, range.lowerBound != name.startIndex { return false }
                cursor = range.upperBound
            }
            if let last = parts.last, !last.isEmpty {
                return name.hasSuffix(last)
            }
            return true
        }
        return name == pattern
    }

    private static func matches(_ source: URL,
                                _ target: URL,
                                strategy: ImportRecipe.EdgeStrategy,
                                labels: [URL: String]) -> Bool {
        switch strategy {
        case .sameDirectory:
            return source.deletingLastPathComponent().path
                == target.deletingLastPathComponent().path
        case .sharedPrefix:
            let a = source.deletingPathExtension().lastPathComponent.lowercased()
            let b = target.deletingPathExtension().lastPathComponent.lowercased()
            let prefix = commonPrefix(a, b)
            return prefix.count >= 3
        case .nameReference:
            // Does the target's label appear in the source file's text?
            let targetLabel = (labels[target]
                               ?? target.deletingPathExtension().lastPathComponent)
                .lowercased()
            guard !targetLabel.isEmpty,
                  let contents = try? String(contentsOf: source, encoding: .utf8)
            else { return false }
            return contents.lowercased().contains(targetLabel)
        }
    }

    private static func commonPrefix(_ a: String, _ b: String) -> String {
        var out = ""
        var ai = a.startIndex
        var bi = b.startIndex
        while ai < a.endIndex, bi < b.endIndex, a[ai] == b[bi] {
            out.append(a[ai])
            ai = a.index(after: ai)
            bi = b.index(after: bi)
        }
        return out
    }

    private static func labelFor(_ file: URL,
                                 strategy: ImportRecipe.LabelStrategy) -> String {
        switch strategy {
        case .basename: return file.deletingPathExtension().lastPathComponent
        case .fullName: return file.lastPathComponent
        }
    }

    // MARK: - Color parsing

    private static func parseColor(_ raw: String) -> Color {
        let named: [String: Color] = [
            "red": .red, "orange": .orange, "yellow": .yellow,
            "green": .green, "mint": .mint, "teal": .teal,
            "cyan": .cyan, "blue": .blue, "indigo": .indigo,
            "purple": .purple, "pink": .pink, "brown": .brown,
            "gray": .gray, "grey": .gray, "white": .white, "black": .black,
        ]
        if let c = named[raw.lowercased()] { return c }
        return AtlasConfig.parseColor(raw) ?? .secondary
    }
}
