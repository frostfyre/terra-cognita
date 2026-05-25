import SwiftUI

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
    var onSelectNode: (String) -> Void

    @State private var showAI = true
    @State private var showMetadata = false
    @State private var showNote = true
    @State private var showOutbound = true
    @State private var showInbound = false
    @State private var followupDraft: String = ""
    @StateObject private var ai = NodeIntelligence()

    var body: some View {
        Group {
            if let node = store.graph.nodes[nodeID] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(node)

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
                            if let md = node.markdownContent, !md.isEmpty {
                                MarkdownBodyView(
                                    source: strippedFrontMatterAndTitle(md),
                                    onWikilinkClick: { slug in
                                        if let resolved = resolveWikilink(slug) {
                                            onSelectNode(resolved)
                                        }
                                    }
                                )
                                .padding(.top, 4)
                            } else {
                                Text("No body").font(.caption).foregroundStyle(.secondary)
                            }
                        } label: {
                            sectionLabel("Note")
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
                            sectionLabel("Outbound", count: outboundEdges(node).count)
                        }

                        DisclosureGroup(isExpanded: $showInbound) {
                            inboundList(node).padding(.top, 4)
                        } label: {
                            sectionLabel("Inbound", count: inboundEdges(node).count)
                        }
                    }
                    .padding()
                }
                .onAppear { ai.prepare(for: node) }
                .onChange(of: nodeID) { _, _ in
                    if let n = store.graph.nodes[nodeID] { ai.prepare(for: n) }
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

    // MARK: - Header

    private func header(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.label)
                .font(.title2).bold()
                .textSelection(.enabled)
            HStack(spacing: 6) {
                if let t = node.type { TagPill(text: t, color: typeColor(t)) }
                if let era = node.era, !era.isEmpty { TagPill(text: era, color: .secondary) }
                if let folder = node.attributes["folder"], folder != node.type.map({ "\($0)s" }) {
                    TagPill(text: folder, color: .secondary)
                }
            }
            HStack(spacing: 12) {
                Button {
                    showAI = true
                    ai.summarize(node: node)
                } label: {
                    Label("Summarize", systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.purple)
                .disabled(!ai.isAvailable)

                if let path = node.filePath {
                    Button("Open in default app") {
                        _ = openFileURL(URL(fileURLWithPath: path))
                    }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    #endif
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String, count: Int? = nil) -> some View {
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
    private func metadataSection(_ node: Node) -> some View {
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

    private func outboundEdges(_ node: Node) -> [Edge] {
        store.graph.edges.filter { $0.sourceID == node.id }
    }
    private func inboundEdges(_ node: Node) -> [Edge] {
        store.graph.edges.filter { $0.targetID == node.id }
    }

    @ViewBuilder
    private func outboundList(_ node: Node) -> some View {
        let edges = outboundEdges(node)
        if edges.isEmpty {
            Text("No outbound links").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(edges, id: \.id) { edge in
                    linkRow(edge: edge, otherID: edge.targetID)
                }
            }
        }
    }

    @ViewBuilder
    private func inboundList(_ node: Node) -> some View {
        let edges = inboundEdges(node)
        if edges.isEmpty {
            Text("No inbound links").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(edges, id: \.id) { edge in
                    linkRow(edge: edge, otherID: edge.sourceID)
                }
            }
        }
    }

    private func linkRow(edge: Edge, otherID: String) -> some View {
        let label = store.graph.nodes[otherID]?.label ?? otherID
        return Button {
            onSelectNode(otherID)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let rel = edge.relationshipType {
                    Text(rel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
                Text(label)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - AI section

    @ViewBuilder
    private func aiSection(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !ai.isAvailable, let note = ai.availabilityNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Transcript of the conversation so far.
            if !ai.messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ai.messages) { message in
                        messageBubble(message)
                    }
                }
            }

            // In-flight indicator + cancel.
            if ai.activity == .running {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { ai.cancel() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            if case .failed(let message) = ai.activity {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Free-form follow-up question — bound to the same session.
            if ai.isAvailable {
                HStack(spacing: 6) {
                    TextField("Ask about this node…", text: $followupDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .lineLimit(1...3)
                        .onSubmit(sendFollowup)
                    Button {
                        sendFollowup()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(followupDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || ai.activity == .running)
                }

                // Quick "explain connection" suggestions for direct neighbours.
                let neighbours = (outboundEdges(node) + inboundEdges(node)).prefix(6)
                if !neighbours.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Explain connection to…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(Array(neighbours), id: \.id) { edge in
                                let otherID = edge.sourceID == node.id ? edge.targetID : edge.sourceID
                                if let other = store.graph.nodes[otherID] {
                                    Button {
                                        ai.explainRelationship(
                                            to: other,
                                            relationshipType: edge.relationshipType,
                                            currentNode: node
                                        )
                                    } label: {
                                        Text(other.label)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(.purple.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.purple)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sendFollowup() {
        let q = followupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let node = store.graph.nodes[nodeID] else { return }
        ai.ask(q, currentNode: node)
        followupDraft = ""
    }

    @ViewBuilder
    private func messageBubble(_ message: NodeIntelligence.Message) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 24)
                Text(message.content)
                    .font(.callout)
                    .padding(8)
                    .background(.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        case .assistant:
            HStack {
                Text(message.content)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                Spacer(minLength: 24)
            }
        case .system:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    /// Strip the YAML front-matter and the first `# heading` so the note body
    /// reads cleanly in the panel (the title is already in `header(_:)`).
    private func strippedFrontMatterAndTitle(_ raw: String) -> String {
        var body = raw
        if body.hasPrefix("---") {
            if let end = body.range(of: "\n---", options: [], range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
                body = String(body[body.index(end.upperBound, offsetBy: 0)...])
                if body.hasPrefix("\n") { body.removeFirst() }
            }
        }
        if let nl = body.firstIndex(of: "\n") {
            let first = body[..<nl].trimmingCharacters(in: .whitespaces)
            if first.hasPrefix("# ") {
                body = String(body[body.index(after: nl)...])
                while body.hasPrefix("\n") { body.removeFirst() }
            }
        }
        return body
    }

    /// Wikilink target (e.g. `Blizzard Entertainment`) -> node id. Case-
    /// insensitive lookup against existing nodes.
    private func resolveWikilink(_ raw: String) -> String? {
        // URL-decoded first
        let decoded = raw.removingPercentEncoding ?? raw
        // Drop a trailing `#section` if present (wikilink to anchor).
        let cleaned = decoded.split(separator: "#").first.map(String.init) ?? decoded
        if store.graph.nodes[cleaned] != nil { return cleaned }
        let lower = cleaned.lowercased()
        return store.graph.nodes.keys.first { $0.lowercased() == lower }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "person": return .cyan
        case "concept": return .yellow
        case "institution": return .mint
        case "event": return .orange
        case "work": return .pink
        default: return .secondary
        }
    }
}

private struct TagPill: View {
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
private struct FlowLayout: Layout {
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
