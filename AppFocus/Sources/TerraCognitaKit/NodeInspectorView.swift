import SwiftUI

/// One-shot intent posted from outside the inspector (typically the
/// per-node radial menu) for the inspector to execute on appear or
/// on next selection change. The inspector clears the binding back
/// to `nil` after it consumes the intent so the same payload doesn't
/// fire twice.
enum InspectorIntent: Equatable {
    case aiOperation(NodeIntelligence.Operation)
    case editBody
    case showMergePicker
}

/// Side-panel inspector for the currently selected node.
///
/// Sections (Metadata / Note / Outbound / Inbound) are individually
/// collapsible. Markdown notes render via `MarkdownBodyView` so headings,
/// lists, links and inline `[[wikilinks]]` come through properly — clicking
/// a wikilink selects that node, completing the navigation loop.
struct NodeInspectorView: View {
    let nodeID: String
    @ObservedObject var store: GraphStore
    /// Called when the user clicks a linked node (either an inbound /
    /// outbound row, or an inline `[[wikilink]]` in the note body).
    /// `nil` means "clear the current selection" (used after delete).
    var onSelectNode: (String?) -> Void
    /// One-shot intent dispatched from outside (e.g. the per-node
    /// radial menu). Consumed and reset to `nil` on receipt.
    var pendingIntent: Binding<InspectorIntent?> = .constant(nil)

    // Visibility note: properties below are `internal` (not `private`)
    // so the per-section extensions in `NodeInspectorView+*.swift`
    // files can read and bind to them. Stays scoped to the
    // TerraCognitaKit module; nothing leaks beyond.
    @State var showAI = true
    @State var showMetadata = false
    @State var showNote = true
    @State var showOutbound = true
    @State var showInbound = false
    @State var followupDraft: String = ""
    @StateObject var ai = NodeIntelligence()

    // Delete + merge confirmation state.
    @State var showingDeleteConfirm = false
    @State var showingMergePicker = false
    @State var mergePickerQuery: String = ""

    // Note editing state. `isEditingNote` toggles the Note disclosure
    // between MarkdownBodyView (read) and a TextEditor (write).
    // `noteDraft` is seeded from the stripped body on entry and written
    // back via `store.updateNodeBody` on Save. `noteSpeech` provides
    // optional mic-driven dictation that appends to whatever the user
    // has already typed.
    @State var isEditingNote = false
    @State var noteDraft: String = ""
    @State var noteSaveError: String?
    @State var noteSpeechPrefix: String = ""
    @StateObject var noteSpeech = SpeechRecognizer()

    /// Drives the unified augment sheet — paste/dictate context for
    /// this node, run the AI, accept/reject the resulting proposals.
    /// Same proposal pipeline as the named operations; the inspector's
    /// proposal list shows results from either entry point.
    @State var showingAugmentSheet = false

    /// Drives the "add link" search-picker sheet — opened from the
    /// `+` pill on the Outbound / Inbound section headers. The
    /// direction is the side that initiated.
    enum AddLinkDirection: String, Identifiable {
        case outbound, inbound
        var id: String { rawValue }
    }
    @State var addingLink: AddLinkDirection?

    var body: some View {
        Group {
            if let node = store.graph.nodes[nodeID] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(node)
                        placeholderPromotionBanner(node)

                        // AI sits right under the header so it's the first
                        // affordance a user sees after selecting a node.
                        DisclosureGroup(isExpanded: $showAI) {
                            aiSection(node).padding(.top, 4)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                Text("AI").font(.headline)
                                if ai.activity == .running {
                                    ProgressView().controlSize(.small).padding(.leading, 4)
                                }
                            }
                        }

                        DisclosureGroup(isExpanded: $showNote) {
                            noteSection(node).padding(.top, 4)
                        } label: {
                            noteSectionLabel(node)
                        }

                        DisclosureGroup(isExpanded: $showMetadata) {
                            metadataSection(node)
                                .padding(.top, 4)
                        } label: {
                            sectionLabel("Metadata")
                        }

                        DisclosureGroup(isExpanded: $showOutbound) {
                            outboundList(node).padding(.top, 4)
                        } label: {
                            edgeSectionLabel(
                                "Outbound",
                                count: outboundEdges(node).count,
                                direction: .outbound
                            )
                        }

                        DisclosureGroup(isExpanded: $showInbound) {
                            inboundList(node).padding(.top, 4)
                        } label: {
                            edgeSectionLabel(
                                "Inbound",
                                count: inboundEdges(node).count,
                                direction: .inbound
                            )
                        }
                    }
                    .padding()
                }
                .onAppear {
                    ai.prepare(for: node)
                    consumePendingIntentIfAny(for: node)
                }
                .onChange(of: nodeID) { _, _ in
                    if let n = store.graph.nodes[nodeID] { ai.prepare(for: n) }
                    // If we're swapping nodes mid-edit, drop the draft —
                    // the user is now looking at a different note.
                    if isEditingNote { cancelNoteEdit() }
                    if let n = store.graph.nodes[nodeID] {
                        consumePendingIntentIfAny(for: n)
                    }
                }
                .onChange(of: pendingIntent.wrappedValue) { _, _ in
                    if let n = store.graph.nodes[nodeID] {
                        consumePendingIntentIfAny(for: n)
                    }
                }
                // Mirror dictated speech into the editor while recording.
                // We append to a snapshot taken at session start so the
                // user's typing isn't blown away.
                .onChange(of: noteSpeech.transcript) { _, newValue in
                    guard noteSpeech.isRecording else { return }
                    let separator = noteSpeechPrefix.isEmpty
                        || noteSpeechPrefix.hasSuffix("\n")
                        || noteSpeechPrefix.hasSuffix(" ")
                        ? "" : " "
                    noteDraft = noteSpeechPrefix + separator + newValue
                }
                .sheet(isPresented: $showingAugmentSheet) {
                    if let n = store.graph.nodes[nodeID] {
                        AugmentNodeSheet(
                            store: store,
                            ai: ai,
                            isPresented: $showingAugmentSheet,
                            node: n
                        )
                    }
                }
                .sheet(item: $addingLink) { direction in
                    addLinkPickerSheet(direction: direction)
                }
            } else {
                ContentUnavailableView(
                    "No node selected",
                    systemImage: "circle.dashed",
                    description: Text("Click a node in the graph to inspect it.")
                )
            }
        }
    }

    @ViewBuilder
    func sectionLabel(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.headline)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    func metadataSection(_ node: Node) -> some View {
        let entries = node.attributes
            .filter { $0.key != "file" && $0.key != "folder" }
            .sorted(by: { $0.key < $1.key })
        if entries.isEmpty {
            Text("No metadata").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries, id: \.key) { key, value in
                    HStack(alignment: .top, spacing: 8) {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        Text(value)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    func outboundEdges(_ node: Node) -> [Edge] {
        store.graph.edges.filter { $0.sourceID == node.id }
    }
    func inboundEdges(_ node: Node) -> [Edge] {
        store.graph.edges.filter { $0.targetID == node.id }
    }

    // MARK: - Placeholder promotion

    /// Banner shown only for synthetic placeholder nodes (created by
    /// the loader's dangling-wikilink extractor). Lets the user
    /// promote the placeholder to one of the atlas's configured
    /// real types — materializes a fresh `.md` file and re-targets
    /// edges in-memory so focus survives the transition.
    @ViewBuilder
    func placeholderPromotionBanner(_ node: Node) -> some View {
        if node.attributes["placeholder"] == "true"
           || node.type?.lowercased() == "placeholder" {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("This is a placeholder")
                        .font(.callout.weight(.medium))
                    Text("A wikilink pointed here but no file exists yet. Promote it to a real node to start editing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(promotableTypes(), id: \.name) { spec in
                            Button {
                                promoteCurrent(to: spec.name, for: node)
                            } label: {
                                Label(spec.displayName ?? spec.name.capitalized,
                                      systemImage: spec.icon)
                            }
                        }
                    } label: {
                        Label("Promote to…", systemImage: "arrow.up.right.square")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!store.canIngest)
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.45), lineWidth: 1)
            )
        }
    }

    /// User-visible types (excludes the synthetic tag / embed /
    /// placeholder entries the config carries for the loader).
    func promotableTypes() -> [AtlasConfig.TypeSpec] {
        let synthetic: Set<String> = ["tag", "embed", "placeholder"]
        return store.config.types.filter {
            !synthetic.contains($0.name.lowercased())
        }
    }

    func promoteCurrent(to typeName: String, for node: Node) {
        switch store.promoteNode(node.id, to: typeName) {
        case .success(let newID):
            // The slug may have changed (e.g. "Frank Frazetta" →
            // "frank-frazetta"); re-select the new id so the
            // inspector follows the promoted node and the canvas
            // re-frames onto it.
            onSelectNode(newID)
        case .failure(let err):
            // Surface the error in the AI status pill — the
            // simplest existing affordance for transient messaging.
            store.loadStatus = err.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Returns true if the post-title body has at least one line that
    /// `MarkdownBodyView` would actually render — i.e. anything other
    /// than blank lines and Dataview edge declarations (which we
    /// filter out of the rendered body since they're surfaced in
    /// Outbound). Used to short-circuit the Note section to a small
    /// placeholder rather than rendering an empty space when a
    /// node's only "body" is its typed edges.
    func hasRenderableProse(_ body: String) -> Bool {
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Match the parser's Dataview-detection: `key:: <…[[…]]…>`.
            if let sep = line.range(of: ":: ") {
                let key = line[..<sep.lowerBound]
                let rest = line[sep.upperBound...]
                if !key.isEmpty,
                   key.allSatisfy({
                       $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
                   }),
                   rest.contains("[[") && rest.contains("]]") {
                    continue
                }
            }
            return true
        }
        return false
    }

    /// Strip the YAML front-matter and the first `# heading` so the note body
    /// reads cleanly in the panel (the title is already in `header(_:)`).
    func strippedFrontMatterAndTitle(_ raw: String) -> String {
        var body = raw
        if body.hasPrefix("---") {
            if let end = body.range(of: "\n---", options: [], range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
                body = String(body[body.index(end.upperBound, offsetBy: 0)...])
                if body.hasPrefix("\n") { body.removeFirst() }
            }
        }
        // Drop any leading blank lines BEFORE looking for the title.
        // GEXF-imported bodies arrive with a `\n# Title…` prefix (the
        // AtlasLoader's frontmatter strip only consumes one leading
        // `\n`), and without this skip the title-strip below sees an
        // empty first line and bails — leaving `# Title` to render as
        // a duplicate H1 inside the Note pane.
        while body.hasPrefix("\n") { body.removeFirst() }
        if let nl = body.firstIndex(of: "\n") {
            let first = body[..<nl].trimmingCharacters(in: .whitespaces)
            if first.hasPrefix("# ") {
                body = String(body[body.index(after: nl)...])
                while body.hasPrefix("\n") { body.removeFirst() }
            }
        } else {
            // Single-line body that is JUST a title — strip it too so
            // the placeholder kicks in rather than rendering a
            // duplicate H1.
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                body = ""
            }
        }
        return body
    }

    /// Resolve an Obsidian embed reference (`sketch.png`, `subfolder/x.pdf`,
    /// etc.) to a file URL the markdown view can render. Searches:
    ///   1. The node's containing folder + relative path
    ///   2. The atlas root + relative path
    ///   3. A recursive search by basename across the atlas (Obsidian-style)
    /// Returns `nil` if nothing matches or no writable atlas is open.
    func resolveEmbed(_ filename: String, for node: Node) -> URL? {
        let fm = FileManager.default
        let cleaned = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // 1. Relative to the node file's directory.
        if let nodePath = node.filePath {
            let nodeDir = URL(fileURLWithPath: nodePath).deletingLastPathComponent()
            let candidate = nodeDir.appendingPathComponent(cleaned)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        // 2. Relative to the atlas root.
        if let atlas = store.writableAtlasURL {
            let candidate = atlas.appendingPathComponent(cleaned)
            if fm.fileExists(atPath: candidate.path) { return candidate }
            // 3. Recursive basename search (Obsidian doesn't require
            //    paths if the filename is unique).
            let basename = (cleaned as NSString).lastPathComponent
            if let enumerator = fm.enumerator(
                at: atlas,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator
                where url.lastPathComponent == basename {
                    return url
                }
            }
        }
        return nil
    }

    /// Wikilink target (e.g. `Blizzard Entertainment`) -> node id. Case-
    /// insensitive lookup against existing nodes.
    func resolveWikilink(_ raw: String) -> String? {
        // URL-decoded first
        let decoded = raw.removingPercentEncoding ?? raw
        // Drop a trailing `#section` if present (wikilink to anchor).
        let cleaned = decoded.split(separator: "#").first.map(String.init) ?? decoded
        if store.graph.nodes[cleaned] != nil { return cleaned }
        let lower = cleaned.lowercased()
        return store.graph.nodes.keys.first { $0.lowercased() == lower }
    }

    func typeColor(_ type: String) -> Color {
        store.config.typeSpec(named: type)?.color ?? .secondary
    }
}

struct TagPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.25), in: Capsule())
    }
}

/// Minimal flow layout — wraps children onto multiple lines when the row
/// width is exhausted. Used for the "explain connection to" chips.
struct InspectorFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = layoutRows(in: width, subviews: subviews)
        return CGSize(width: result.width, height: result.totalHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let result = layoutRows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in result.rows {
            var x = bounds.minX
            for (subview, size) in row {
                subview.place(at: CGPoint(x: x, y: y),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += (row.first?.1.height ?? 0) + spacing
        }
    }

    private struct LayoutResult {
        var rows: [[(LayoutSubview, CGSize)]] = []
        var width: CGFloat = 0
        var totalHeight: CGFloat = 0
    }

    private func layoutRows(in width: CGFloat, subviews: Subviews) -> LayoutResult {
        var result = LayoutResult()
        var currentRow: [(LayoutSubview, CGSize)] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if needed > width && !currentRow.isEmpty {
                result.rows.append(currentRow)
                result.width = max(result.width, rowWidth)
                result.totalHeight += rowHeight + spacing
                currentRow = []
                rowWidth = 0
                rowHeight = 0
            }
            currentRow.append((subview, size))
            rowWidth = currentRow.count == 1 ? size.width : rowWidth + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }
        if !currentRow.isEmpty {
            result.rows.append(currentRow)
            result.width = max(result.width, rowWidth)
            result.totalHeight += rowHeight
        }
        return result
    }
}
