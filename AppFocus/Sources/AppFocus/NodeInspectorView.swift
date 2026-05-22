import SwiftUI

/// Side-panel inspector for the currently selected node.
///
/// Shows the markdown body, YAML metadata, and clickable inbound /
/// outbound link lists so the inspector doubles as a navigation surface
/// (clicking a linked node selects it).
struct NodeInspectorView: View {
    let nodeID: String
    @ObservedObject var store: GraphStore
    /// Called when the user clicks one of the inbound / outbound link rows.
    var onSelectNode: (String) -> Void

    var body: some View {
        Group {
            if let node = store.graph.nodes[nodeID] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(node)
                        metadataSection(node)
                        if let md = node.markdownContent, !md.isEmpty {
                            Divider()
                            Text("Note").font(.headline)
                            Text(strippedFrontMatterAndTitle(md))
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        linksSection(node)
                    }
                    .padding()
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

    // MARK: - Sections

    private func header(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.label).font(.title2).bold()
                .textSelection(.enabled)
            HStack(spacing: 6) {
                if let t = node.type { TagPill(text: t, color: typeColor(t)) }
                if let era = node.era, !era.isEmpty { TagPill(text: era, color: .secondary) }
                if let folder = node.attributes["folder"], folder != node.type.map { "\($0)s" } {
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

    private func metadataSection(_ node: Node) -> some View {
        let entries = node.attributes
            .filter { $0.key != "file" && $0.key != "folder" }
            .sorted(by: { $0.key < $1.key })
        return Group {
            if !entries.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Metadata").font(.headline)
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
    }

    private func linksSection(_ node: Node) -> some View {
        let outbound = store.graph.edges.filter { $0.sourceID == node.id }
        let inbound = store.graph.edges.filter { $0.targetID == node.id }
        return VStack(alignment: .leading, spacing: 10) {
            if !outbound.isEmpty {
                Text("Outbound (\(outbound.count))")
                    .font(.headline)
                ForEach(outbound, id: \.id) { edge in
                    linkRow(edge: edge, otherID: edge.targetID)
                }
            }
            if !inbound.isEmpty {
                Text("Inbound (\(inbound.count))")
                    .font(.headline)
                    .padding(.top, outbound.isEmpty ? 0 : 4)
                ForEach(inbound, id: \.id) { edge in
                    linkRow(edge: edge, otherID: edge.sourceID)
                }
            }
            if outbound.isEmpty && inbound.isEmpty {
                Text("No links")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        // Drop the first H1 heading line, if present.
        if let nl = body.firstIndex(of: "\n") {
            let first = body[..<nl].trimmingCharacters(in: .whitespaces)
            if first.hasPrefix("# ") {
                body = String(body[body.index(after: nl)...])
                while body.hasPrefix("\n") { body.removeFirst() }
            }
        }
        return body
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
