import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(AVKit)
import AVKit
#endif

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
/// inspector. `[[target|alias]]` is supported. Obsidian-style embeds
/// (`![[filename.png]]`) are extracted as their own blocks and
/// rendered via `resolveEmbed` — images inline, PDFs / videos as
/// type-appropriate previews, anything else as a file chip.
struct MarkdownBodyView: View {
    let source: String
    /// Called when the user clicks a `[[wikilink]]` rendered inline.
    var onWikilinkClick: ((String) -> Void)?
    /// Resolve an embed filename (e.g. `sketch_bar.png`) to a file URL.
    /// `nil` skips rendering. Closure usually searches the node file's
    /// directory and the vault root.
    var resolveEmbed: ((String) -> URL?)? = nil
    /// The currently-open vault URL, when available. Used to bracket
    /// security-scoped access around image embed loads — without
    /// this, iOS silently fails to read files inside the vault even
    /// though the URL is correct. macOS treats the bracket as a
    /// no-op for non-sandboxed apps, so it's safe across platforms.
    var vaultURL: URL? = nil

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
        /// Obsidian embed: `![[filename]]` or `![[filename|alt text]]`.
        case embed(filename: String, alt: String?)
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

        case .embed(let filename, let alt):
            embedView(filename: filename, alt: alt)
        }
    }

    @ViewBuilder
    private func embedView(filename: String, alt: String?) -> some View {
        let url = resolveEmbed?(filename)
        if let url {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff":
                ScopedImageView(url: url,
                                vaultURL: vaultURL,
                                fallback: { embedFallback(filename, url: url, alt: alt) })
                if let alt, !alt.isEmpty {
                    Text(alt).font(.caption2).foregroundStyle(.secondary)
                }

            #if canImport(PDFKit)
            case "pdf":
                PDFThumbView(url: url)
                    .frame(height: 200)
                    .cornerRadius(6)
                    .overlay(alignment: .topTrailing) {
                        openInDefaultButton(url: url)
                    }
            #endif

            #if canImport(AVKit)
            case "mp4", "mov", "m4v":
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 220)
                    .cornerRadius(6)
            case "mp3", "m4a", "wav", "aac", "aiff":
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 60)
            #endif

            default:
                embedFallback(filename, url: url, alt: alt)
            }
        } else {
            // Unresolvable — show a faded chip so it's clear something
            // was embedded but the file couldn't be located.
            HStack(spacing: 6) {
                Image(systemName: "questionmark.square.dashed")
                Text(filename).font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func embedFallback(_ filename: String, url: URL, alt: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForFile(url))
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(alt ?? filename).font(.callout)
                Text(filename).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            openInDefaultButton(url: url)
        }
        .padding(8)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func openInDefaultButton(url: URL) -> some View {
        Button {
            _ = openFileURL(url)
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .padding(4)
    }

    private func iconForFile(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "mp4", "mov", "m4v": return "film"
        case "mp3", "m4a", "wav", "aac", "aiff": return "music.note"
        case "zip", "tar", "gz": return "archivebox"
        default: return "doc"
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

        // Pre-process: split inline `![[...]]` embeds onto their own
        // lines so they become standalone blocks. Obsidian sometimes
        // tucks embeds mid-paragraph; this is the cheapest way to keep
        // them out of paragraph-text rendering.
        let preprocessed = explodeEmbeds(raw)

        for line in preprocessed.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                flushBullets()
                continue
            }

            // Dataview-style edge declarations (`key:: [[target]]`) are
            // already surfaced as typed edges in the Inspector's
            // Outbound section — rendering them here too would (a)
            // duplicate content the user has elsewhere and (b) on iOS
            // the layout collapses successive single-newline-separated
            // lines into one run-on paragraph, which looks broken. We
            // flush any in-flight paragraph and skip the line.
            if Self.isDataviewEdgeLine(trimmed) {
                flushParagraph(); flushBullets()
                continue
            }

            // Embed — line containing ONLY an `![[...]]` marker.
            if let embed = parseEmbedLine(trimmed) {
                flushParagraph(); flushBullets()
                blocks.append(.embed(filename: embed.filename, alt: embed.alt))
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

    /// Split any inline `![[…]]` markers onto their own lines so the
    /// parser can treat them as standalone blocks. Idempotent — running
    /// it twice produces the same output.
    private static func explodeEmbeds(_ raw: String) -> String {
        guard raw.contains("![[") else { return raw }
        let pattern = #"!\[\[[^\]\n]+\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return raw }
        var out = ""
        var cursor = 0
        for m in matches {
            if cursor < m.range.location {
                let chunk = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                out += chunk
                if !chunk.hasSuffix("\n") { out += "\n" }
            }
            out += ns.substring(with: m.range)
            out += "\n"
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            out += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return out
    }

    /// True if the line is a Dataview-style edge declaration —
    /// `key:: [[target]]` where `key` is alphanumeric / dash /
    /// underscore. We only treat it as such when the value side
    /// contains a wikilink, so prose lines like "ratio:: 3:4" don't
    /// get filtered. The loader picks these up as typed edges; the
    /// Inspector renders them in the Outbound list. Rendering them
    /// in the body too is redundant and breaks layout on iOS where
    /// consecutive single-newline lines collapse into one paragraph.
    private static func isDataviewEdgeLine(_ line: String) -> Bool {
        guard let sepRange = line.range(of: ":: ") else { return false }
        let key = line[..<sepRange.lowerBound]
        guard !key.isEmpty,
              key.allSatisfy({
                  $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
              })
        else { return false }
        let rest = line[sepRange.upperBound...]
        return rest.contains("[[") && rest.contains("]]")
    }

    private static func parseEmbedLine(_ line: String) -> (filename: String, alt: String?)? {
        guard line.hasPrefix("![[") && line.hasSuffix("]]") else { return nil }
        let inner = String(line.dropFirst(3).dropLast(2))
        let parts = inner.split(separator: "|", maxSplits: 1)
        let filename = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let alt = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : nil
        guard !filename.isEmpty else { return nil }
        return (filename, alt)
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

// MARK: - PDF preview wrapper

#if canImport(PDFKit)
/// Cross-platform single-page PDF preview. Shows the first page,
/// scaled to fit. Tap-through to open in default app is the caller's
/// responsibility (we overlay an arrow button up in `embedView`).
struct PDFThumbView: View {
    let url: URL
    var body: some View {
        #if os(macOS)
        PDFThumbNSView(url: url)
        #else
        PDFThumbUIView(url: url)
        #endif
    }
}

/// Inline image embed that handles iOS security-scoped resource
/// access. SwiftUI's `AsyncImage(url:)` uses `URLSession.shared`
/// under the hood, which cannot read from sandboxed vault folders
/// on iOS — the load silently fails. This view brackets
/// `startAccessingSecurityScopedResource()` on the vault URL,
/// reads the bytes, builds a platform image, and renders.
private struct ScopedImageView<Fallback: View>: View {
    let url: URL
    let vaultURL: URL?
    let fallback: () -> Fallback

    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .cornerRadius(6)
            } else if failed {
                fallback()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task { await loadImage() }
            }
        }
    }

    private func loadImage() async {
        let target = url
        let vault = vaultURL
        let loaded: Image? = await Task.detached(priority: .userInitiated) {
            let didStart = vault?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didStart { vault?.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: target) else { return nil }
            #if canImport(AppKit)
            if let ns = NSImage(data: data) {
                return Image(nsImage: ns)
            }
            #elseif canImport(UIKit)
            if let ui = UIImage(data: data) {
                return Image(uiImage: ui)
            }
            #endif
            return nil
        }.value
        if let loaded {
            self.image = loaded
        } else {
            self.failed = true
        }
    }
}

#if os(macOS)
private struct PDFThumbNSView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.displaysPageBreaks = false
        v.document = PDFDocument(url: url)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url {
            v.document = PDFDocument(url: url)
        }
    }
}
#else
private struct PDFThumbUIView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.displaysPageBreaks = false
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url {
            v.document = PDFDocument(url: url)
        }
    }
}
#endif
#endif
