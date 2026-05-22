import SwiftUI

/// Lightweight block-level renderer for the vault's markdown notes.
///
/// SwiftUI's built-in `Text(_ markdown: LocalizedStringKey)` renders inline
/// markdown (bold/italic/links/code) but ignores block constructs like
/// headings and lists. This view walks the source line-by-line and emits
/// an appropriate SwiftUI view per block, while inline markdown inside
/// each block is still handled by SwiftUI's parser.
///
/// `[[wikilinks]]` are rewritten to `appfocus://node/<slug>` links so
/// clicks can navigate via the SwiftUI `OpenURLAction` injected by the
/// inspector. `[[target|alias]]` is supported.
struct MarkdownBodyView: View {
    let source: String
    /// Called when the user clicks a `[[wikilink]]` rendered inline.
    var onWikilinkClick: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { i in
                block(blocks[i])
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "appfocus", url.host == "node" {
                let target = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !target.isEmpty {
                    onWikilinkClick?(target)
                    return .handled
                }
            }
            return .systemAction
        })
    }

    // MARK: - Block model

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(items: [String])
        case quote(text: String)
        case paragraph(text: String)
    }

    private var blocks: [Block] {
        Self.parse(source)
    }

    @ViewBuilder
    private func block(_ b: Block) -> some View {
        switch b {
        case .heading(let level, let text):
            Text(Self.attributed(text))
                .font(headingFont(level: level))
                .padding(.top, level <= 2 ? 6 : 2)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(Self.attributed(items[i]))
                            .textSelection(.enabled)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(.secondary).frame(width: 2)
                Text(Self.attributed(text))
                    .italic()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.leading, 2)

        case .paragraph(let text):
            Text(Self.attributed(text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:  return .title2.weight(.semibold)
        case 2:  return .title3.weight(.semibold)
        case 3:  return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    // MARK: - Parsing

    /// Walk the source line-by-line, collecting consecutive paragraph/list
    /// lines into single blocks. Headings and blockquotes are one block
    /// per line. Blank lines flush the current paragraph.
    private static func parse(_ raw: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var bulletLines: [String] = []

        func flushParagraph() {
            if !paragraphLines.isEmpty {
                let joined = paragraphLines.joined(separator: " ")
                blocks.append(.paragraph(text: rewriteWikilinks(joined)))
                paragraphLines.removeAll()
            }
        }
        func flushBullets() {
            if !bulletLines.isEmpty {
                blocks.append(.bullet(items: bulletLines.map(rewriteWikilinks)))
                bulletLines.removeAll()
            }
        }

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                flushBullets()
                continue
            }

            // Heading
            if let hashCount = leadingHashCount(trimmed), hashCount > 0, hashCount <= 6 {
                flushParagraph(); flushBullets()
                let text = String(trimmed.dropFirst(hashCount))
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: hashCount, text: rewriteWikilinks(text)))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                flushParagraph(); flushBullets()
                let text = String(trimmed.dropFirst(2))
                blocks.append(.quote(text: rewriteWikilinks(text)))
                continue
            }

            // Bullet — `- `, `* `, `+ `, or numbered.
            if isBullet(trimmed) {
                flushParagraph()
                let text = stripBulletPrefix(trimmed)
                bulletLines.append(text)
                continue
            }

            // Plain paragraph line — accumulate.
            flushBullets()
            paragraphLines.append(trimmed)
        }
        flushParagraph()
        flushBullets()
        return blocks
    }

    private static func leadingHashCount(_ s: String) -> Int? {
        guard s.hasPrefix("#") else { return nil }
        var count = 0
        for ch in s {
            if ch == "#" { count += 1 } else { break }
        }
        // Must be followed by whitespace to count as a heading.
        if count >= s.count { return nil }
        let next = s[s.index(s.startIndex, offsetBy: count)]
        return next.isWhitespace ? count : nil
    }

    private static func isBullet(_ s: String) -> Bool {
        if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") { return true }
        // Numbered list: "1. " "2. " etc.
        var i = s.startIndex
        var sawDigit = false
        while i < s.endIndex, s[i].isNumber { sawDigit = true; i = s.index(after: i) }
        if sawDigit, i < s.endIndex, s[i] == "." {
            let after = s.index(after: i)
            if after < s.endIndex, s[after] == " " { return true }
        }
        return false
    }

    private static func stripBulletPrefix(_ s: String) -> String {
        if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") {
            return String(s.dropFirst(2))
        }
        if let dot = s.firstIndex(of: ".") {
            let after = s.index(after: dot)
            if after < s.endIndex, s[after] == " " {
                return String(s[s.index(after: after)...])
            }
        }
        return s
    }

    /// Convert `[[target]]` and `[[target|alias]]` into markdown links
    /// pointing at `appfocus://node/<target>`. The `OpenURLAction` in
    /// `body` traps clicks on these.
    private static func rewriteWikilinks(_ s: String) -> String {
        guard s.contains("[[") else { return s }
        let pattern = #"\[\[([^\]\n|#]+)(?:#[^\]\n|]*)?(?:\|([^\]\n]+))?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var result = ""
        var cursor = 0
        for m in matches {
            let target = ns.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            let alias: String = {
                let r = m.range(at: 2)
                if r.location != NSNotFound {
                    return ns.substring(with: r).trimmingCharacters(in: .whitespaces)
                }
                return target
            }()
            // Append the text before this match.
            if cursor < m.range.location {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            }
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            result += "[\(alias)](appfocus://node/\(encoded))"
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }

    /// Parse a paragraph's inline markdown into an AttributedString.
    /// Falls back to a plain string if the parse fails (e.g. malformed
    /// markdown).
    private static func attributed(_ s: String) -> AttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.allowsExtendedAttributes = true
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let parsed = try? AttributedString(markdown: s, options: opts) {
            return parsed
        }
        return AttributedString(s)
    }
}
