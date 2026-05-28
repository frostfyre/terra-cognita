import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Per-atlas ontology — declared by the atlas in `.terracognita/config.yaml`,
/// loaded alongside the graph. Lets users define their own type
/// vocabulary, era taxonomy, and other semantic decisions instead of
/// inheriting the bundled defaults (people / concepts / institutions /
/// events / works + the heritage-era enum).
///
/// Missing config → the `Self.default` returned, which preserves the
/// behavior every existing atlas has today.
struct AtlasConfig: Equatable {
    /// Which mode this atlas was created in. Persisted as a top-level
    /// `mode: <raw>` line in `.terracognita/config.yaml`. Older atlases
    /// (no mode tag) load as `.continuity` — the only mode that
    /// existed before Phase 2.
    var mode: Mode = .continuity
    var types: [TypeSpec]
    var eras: [EraSpec]
    var extractors: Extractors

    struct TypeSpec: Equatable, Identifiable {
        var name: String                  // canonical front-matter value, lowercased
        var displayName: String?          // optional pretty name; falls back to name.capitalized
        var color: Color
        var icon: String                  // SF Symbol
        var folder: String?               // optional subfolder convention
        var id: String { name }
    }

    struct EraSpec: Equatable, Identifiable {
        var name: String
        var weight: Double                // ordinal position; 0 = deepest
        var id: String { name }
    }

    /// Toggles for the loader's synthetic-node extractors. Each one
    /// surfaces structure that doesn't live in `[[wikilinks]]` —
    /// matching the kinds of node Obsidian's graph view shows. All
    /// default to `true`; users can opt-out per-atlas via config.
    struct Extractors: Equatable {
        /// Promote `#tag` references to first-class tag nodes; each
        /// note that uses a tag gets an edge to it.
        var tags: Bool = true
        /// Promote `![[file.png]]` embeds to file nodes; each note
        /// embedding the file gets an edge to it.
        var embeds: Bool = true
        /// Surface `[[Name]]` targets that have no matching `.md` as
        /// hollow placeholder nodes (Obsidian convention).
        var placeholders: Bool = true
    }

    // MARK: - Defaults (the original hardcoded ontology)

    static let `default` = AtlasConfig(
        mode: .continuity,
        types: [
            TypeSpec(name: "person",      color: .cyan,   icon: "person.fill",      folder: "people"),
            TypeSpec(name: "concept",     color: .yellow, icon: "lightbulb.fill",   folder: "concepts"),
            TypeSpec(name: "institution", color: .mint,   icon: "building.2.fill",  folder: "institutions"),
            TypeSpec(name: "event",       color: .orange, icon: "calendar",         folder: "events"),
            TypeSpec(name: "work",        color: .pink,   icon: "book.fill",        folder: "works"),
            // Synthetic types — the loader's extractors stamp these
            // onto nodes that don't come from `.md` files. Custom
            // configs that omit these still get a sensible fallback
            // color because the typeSpec lookup is case-insensitive
            // and missing types fall through to white.
            TypeSpec(name: "tag",         color: .green,  icon: "tag.fill",                 folder: nil),
            TypeSpec(name: "embed",       color: .indigo, icon: "photo.fill",               folder: nil),
            TypeSpec(name: "placeholder", color: .gray,   icon: "questionmark.circle.fill", folder: nil),
        ],
        eras: [
            EraSpec(name: "pre-conscious",           weight: 0),
            EraSpec(name: "self-choosing-childhood", weight: 1),
            EraSpec(name: "pre-blizzard",            weight: 2),
            EraSpec(name: "early-career",            weight: 3),
            EraSpec(name: "blizzard-era",            weight: 4),
            EraSpec(name: "bridge",                  weight: 5),
            EraSpec(name: "post-formation",          weight: 6),
            EraSpec(name: "post-blizzard",           weight: 7),
            EraSpec(name: "current",                 weight: 8),
            EraSpec(name: "career-spanning",         weight: 6.5),
        ],
        extractors: Extractors()
    )

    // MARK: - Lookup helpers

    func typeSpec(named name: String?) -> TypeSpec? {
        guard let name else { return nil }
        let needle = name.lowercased()
        return types.first { $0.name.lowercased() == needle }
    }

    func eraSpec(named name: String?) -> EraSpec? {
        guard let name else { return nil }
        let needle = name.lowercased()
        return eras.first { $0.name.lowercased() == needle }
    }

    /// All era names in declaration order (used by composer + edit menu).
    var eraTagValues: [String] { eras.map(\.name) }

    /// Maximum era weight — denominator for normalized depth.
    var maxEraWeight: Double { eras.map(\.weight).max() ?? 8 }

    // MARK: - Loading

    /// Resolve an atlas's config by checking `.terracognita/config.yaml`
    /// (preferred) then `.terracognita/config.yml`. Returns `.default`
    /// if no file exists or parsing fails — existing atlases always
    /// keep working.
    static func load(from atlasURL: URL) -> AtlasConfig {
        let dir = atlasURL.appendingPathComponent(".terracognita")
        for filename in ["config.yaml", "config.yml"] {
            let candidate = dir.appendingPathComponent(filename)
            if let raw = try? String(contentsOf: candidate, encoding: .utf8) {
                if let parsed = parse(yaml: raw) {
                    return parsed
                }
            }
        }
        return .default
    }

    /// Write this config to `.terracognita/config.yaml` in the given
    /// atlas. Used by `AtlasSettingsSheet` — saves the in-app edits
    /// back to the source-of-truth file.
    func save(to atlasURL: URL) throws {
        let dir = atlasURL.appendingPathComponent(".terracognita")
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("config.yaml")
        try serialize().write(to: target, atomically: true, encoding: .utf8)
    }

    /// Render this config as YAML matching the parser's accepted shape.
    /// Excludes the synthetic tag/embed/placeholder types (they're
    /// always merged in at load time, so we don't need them on disk).
    func serialize() -> String {
        var lines: [String] = [
            "# Terra Cognita atlas configuration.",
            "# Generated by the Atlas Settings editor.",
            "",
            "mode: \(mode.rawValue)",
            "",
        ]
        let syntheticNames: Set<String> = ["tag", "embed", "placeholder"]
        let userTypes = types.filter { !syntheticNames.contains($0.name) }
        if !userTypes.isEmpty {
            lines.append("types:")
            for t in userTypes {
                lines.append("  - name: \(yamlEscape(t.name))")
                if let dn = t.displayName, !dn.isEmpty {
                    lines.append("    displayName: \(yamlEscape(dn))")
                }
                lines.append("    color: \(yamlEscape(serializeColor(t.color)))")
                lines.append("    icon: \(yamlEscape(t.icon))")
                if let folder = t.folder, !folder.isEmpty {
                    lines.append("    folder: \(yamlEscape(folder))")
                }
            }
            lines.append("")
        }
        if !eras.isEmpty {
            lines.append("eras:")
            for e in eras {
                lines.append("  - name: \(yamlEscape(e.name))")
                lines.append("    weight: \(e.weight)")
            }
            lines.append("")
        }
        lines.append("extractors:")
        lines.append("  tags: \(extractors.tags)")
        lines.append("  embeds: \(extractors.embeds)")
        lines.append("  placeholders: \(extractors.placeholders)")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func yamlEscape(_ raw: String) -> String {
        let needsQuoting = raw.contains(":") || raw.contains("#") ||
                           raw.contains("\"") || raw.hasPrefix(" ") ||
                           raw.hasSuffix(" ") || raw.hasPrefix("-") ||
                           raw.isEmpty
        if !needsQuoting { return raw }
        return "\"\(raw.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// Best-effort color → hex serialization. Cross-platform via
    /// NSColor / UIColor bridging. Falls back to a SwiftUI named color
    /// for the defaults so the YAML stays human-friendly.
    private func serializeColor(_ color: Color) -> String {
        // Quick named-color match for the common defaults so output
        // reads as `cyan` rather than `#00FFFF`.
        let knownPairs: [(Color, String)] = [
            (.red, "red"), (.orange, "orange"), (.yellow, "yellow"),
            (.green, "green"), (.mint, "mint"), (.teal, "teal"),
            (.cyan, "cyan"), (.blue, "blue"), (.indigo, "indigo"),
            (.purple, "purple"), (.pink, "pink"), (.brown, "brown"),
            (.gray, "gray"), (.white, "white"), (.black, "black"),
        ]
        for (c, name) in knownPairs where color == c { return name }
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return hexString(r: r, g: g, b: b)
        #elseif canImport(AppKit)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        return hexString(r: r, g: g, b: b)
        #else
        return "gray"
        #endif
    }

    private func hexString(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        let ri = Int((max(0, min(1, r)) * 255).rounded())
        let gi = Int((max(0, min(1, g)) * 255).rounded())
        let bi = Int((max(0, min(1, b)) * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

// MARK: - Tiny YAML parser (covers our schema only)

extension AtlasConfig {
    /// Schema-specific YAML parser. Handles top-level keys with
    /// list-of-mapping values:
    /// ```
    /// types:
    ///   - name: character
    ///     color: "#7DD3FC"
    ///     icon: person.fill
    ///   - name: location
    ///     ...
    /// eras:
    ///   - name: pre-game
    ///     weight: 0
    /// ```
    /// Anything outside that shape is ignored. Returns `nil` on
    /// unrecoverable parse failure so the caller can fall back to defaults.
    static func parse(yaml raw: String) -> AtlasConfig? {
        var typeSpecs: [TypeSpec] = []
        var eraSpecs: [EraSpec] = []
        var extractors = Extractors()
        var mode: Mode = .continuity

        enum Section { case none, types, eras, extractors }
        var section: Section = .none
        var current: [String: String] = [:]

        func flush() {
            defer { current.removeAll() }
            guard !current.isEmpty else { return }
            switch section {
            case .types:
                guard let name = current["name"], !name.isEmpty else { return }
                let color = parseColor(current["color"]) ?? .secondary
                let icon = current["icon"] ?? "circle.fill"
                let folder = current["folder"]
                let displayName = current["displayName"]
                typeSpecs.append(TypeSpec(
                    name: name.lowercased(),
                    displayName: displayName,
                    color: color,
                    icon: icon,
                    folder: folder
                ))
            case .eras:
                guard let name = current["name"], !name.isEmpty else { return }
                let weight = Double(current["weight"] ?? "") ?? Double(eraSpecs.count)
                eraSpecs.append(EraSpec(name: name, weight: weight))
            case .extractors, .none:
                break
            }
        }

        func parseBool(_ s: String) -> Bool? {
            switch s.lowercased() {
            case "true", "yes", "on", "1":  return true
            case "false", "no", "off", "0": return false
            default: return nil
            }
        }

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Strip comments and trailing whitespace.
            let stripped: String = {
                if let hashIdx = line.firstIndex(of: "#") {
                    // Only strip if # is unquoted (cheap heuristic: not preceded by ").
                    let before = line[..<hashIdx]
                    if !before.contains("\"") {
                        return String(before).trimmingCharacters(in: .whitespaces)
                    }
                }
                return line.trimmingCharacters(in: .whitespaces)
            }()
            if stripped.isEmpty { continue }
            let indent = line.prefix { $0 == " " }.count

            // Top-level section headers (and the scalar `mode:` line).
            if indent == 0 {
                flush()
                switch stripped {
                case "types:":      section = .types
                case "eras:":       section = .eras
                case "extractors:": section = .extractors
                default:
                    section = .none
                    // Scalar top-level keys land here. We currently
                    // only recognize `mode: <raw>`.
                    if let (k, v) = parseKV(stripped),
                       k.lowercased() == "mode",
                       let parsed = Mode(rawValue: v.lowercased()) {
                        mode = parsed
                    }
                }
                continue
            }

            // Inside a section: lines beginning with "- " start a new entry.
            if section != .none {
                if stripped.hasPrefix("- ") {
                    flush()
                    let rest = String(stripped.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if let (k, v) = parseKV(rest) { current[k] = v }
                    continue
                }
                if section == .extractors {
                    // `extractors:` is a flat map of booleans.
                    if let (k, v) = parseKV(stripped), let b = parseBool(v) {
                        switch k.lowercased() {
                        case "tags":         extractors.tags = b
                        case "embeds":       extractors.embeds = b
                        case "placeholders": extractors.placeholders = b
                        default: break
                        }
                    }
                    continue
                }
                if let (k, v) = parseKV(stripped) { current[k] = v }
            }
        }
        flush()

        // Empty file → treat as parse failure so caller falls back to defaults.
        guard !(typeSpecs.isEmpty && eraSpecs.isEmpty) else { return nil }

        // Always ensure the synthetic types (tag/embed/placeholder)
        // are present so the extractors have somewhere to render to.
        // User overrides win — if the config defines its own `tag`,
        // that wins; otherwise the default is appended.
        var mergedTypes = typeSpecs.isEmpty ? AtlasConfig.default.types : typeSpecs
        let presentNames = Set(mergedTypes.map { $0.name.lowercased() })
        for synthetic in ["tag", "embed", "placeholder"] {
            if !presentNames.contains(synthetic),
               let spec = AtlasConfig.default.types.first(where: { $0.name == synthetic }) {
                mergedTypes.append(spec)
            }
        }

        return AtlasConfig(
            mode: mode,
            types: mergedTypes,
            eras:  eraSpecs.isEmpty  ? AtlasConfig.default.eras  : eraSpecs,
            extractors: extractors
        )
    }

    private static func parseKV(_ s: String) -> (String, String)? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let key = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
        var value = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        // Strip wrapping quotes if any.
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }

    /// Parses `#RRGGBB`, `#RRGGBBAA`, or a named SwiftUI color (red,
    /// blue, etc.) into a SwiftUI Color.
    static func parseColor(_ raw: String?) -> Color? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            return colorFromHex(String(trimmed.dropFirst()))
        }
        switch trimmed.lowercased() {
        case "red":     return .red
        case "orange":  return .orange
        case "yellow":  return .yellow
        case "green":   return .green
        case "mint":    return .mint
        case "teal":    return .teal
        case "cyan":    return .cyan
        case "blue":    return .blue
        case "indigo":  return .indigo
        case "purple":  return .purple
        case "pink":    return .pink
        case "brown":   return .brown
        case "gray", "grey": return .gray
        case "white":   return .white
        case "black":   return .black
        case "primary", "secondary": return .secondary
        default:        return nil
        }
    }

    private static func colorFromHex(_ hex: String) -> Color? {
        var s = hex
        // Allow short form #RGB.
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8 else { return nil }
        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xff) / 255.0
            g = Double((v >> 8)  & 0xff) / 255.0
            b = Double(v         & 0xff) / 255.0
            a = 1.0
        } else {
            r = Double((v >> 24) & 0xff) / 255.0
            g = Double((v >> 16) & 0xff) / 255.0
            b = Double((v >> 8)  & 0xff) / 255.0
            a = Double(v         & 0xff) / 255.0
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
