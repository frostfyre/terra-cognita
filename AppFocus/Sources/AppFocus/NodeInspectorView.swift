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

    @State private var showMetadata = true
    @State private var showNote = true
    @State private var showOutbound = true
    @State private var showInbound = false
    @State private var showAI = false
    @StateObject private var ai = NodeIntelligence()

    var body: some View {
        Group {
            if let node = store.graph.nodes[nodeID] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(node)

                        DisclosureGroup(isExpanded: $showMetadata) {
                            metadataSection(node)
                                .padding(.top, 4)
                        } label: {
                            sectionLabel("Metadata")
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

                        DisclosureGroup(isExpanded: $showAI) {
                            aiSection(node).padding(.top, 4)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                Text("AI").font(.headline)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: nodeID) { _, _ in
                    // Reset the AI panel when navigating to a different node
                    // so we don't leave a stale summary on screen.
                    ai.cancel()
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
            if let path = node.filePath {
                Button("Open in default app") {
                    _ = openFileURL(URL(fileURLWithPath: path))
                }
                .buttonStyle(.link)
                .font(.caption)
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
        VStack(alignment: .leading, spacing: 8) {
            if !ai.isAvailable, let note = ai.availabilityNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    ai.summarize(node: node)
                } label: {
                    Label("Summarize this note", systemImage: "sparkles")
                }
                .disabled(!ai.isAvailable
                          || (node.markdownContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || ai.status == .running)

                if ai.status == .running {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { ai.cancel() }
                        .buttonStyle(.borderless)
                }
            }

            switch ai.status {
            case .idle:
                EmptyView()
            case .running:
                Text("Thinking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .finished(let text):
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .unavailable(let message):
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Quick "explain connection" affordance, one row per neighbor.
            let neighbors = outboundEdges(node) + inboundEdges(node)
            if ai.isAvailable && !neighbors.isEmpty {
                Divider()
                Text("Explain connection to…").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(neighbors.prefix(6)), id: \.id) { edge in
                    let otherID = edge.sourceID == node.id ? edge.targetID : edge.sourceID
                    if let other = store.graph.nodes[otherID] {
                        Button {
                            ai.explainRelationship(
                                from: node,
                                to: other,
                                relationshipType: edge.relationshipType
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle")
                                Text(other.label).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.purple)
                        .font(.caption)
                    }
                }
            }
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
