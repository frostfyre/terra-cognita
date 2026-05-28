import SwiftUI

/// Outbound / Inbound lists + the per-edge link row, including the
/// relationship-type menu and the trash button. Edge editing only
/// makes sense from the source note's inspector, so the affordances
/// (menu / trash) only render on outbound rows.
extension NodeInspectorView {

    @ViewBuilder
    func outboundList(_ node: Node) -> some View {
        let edges = outboundEdges(node)
        if edges.isEmpty {
            Text("No outbound links").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(edges, id: \.id) { edge in
                    linkRow(edge: edge, otherID: edge.targetID, isOutbound: true)
                }
            }
        }
    }

    @ViewBuilder
    func inboundList(_ node: Node) -> some View {
        let edges = inboundEdges(node)
        if edges.isEmpty {
            Text("No inbound links").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(edges, id: \.id) { edge in
                    linkRow(edge: edge, otherID: edge.sourceID, isOutbound: false)
                }
            }
        }
    }

    @ViewBuilder
    func linkRow(edge: Edge, otherID: String, isOutbound: Bool) -> some View {
        let label = store.graph.nodes[otherID]?.label ?? otherID
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Relationship pill — tappable Menu on outbound edges
            // (we can rewrite the source note); static on inbound
            // (would need to edit a *different* note, surface in
            // that node's inspector instead).
            if isOutbound && store.canIngest && !isSynthetic(edge) {
                edgeRelationshipMenu(edge: edge)
            } else if let rel = edge.relationshipType {
                Text(rel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            Button {
                onSelectNode(otherID)
            } label: {
                Text(label)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOutbound && store.canIngest && !isSynthetic(edge) {
                Button {
                    if let err = store.removeEdge(edge) {
                        store.loadStatus = err
                    } else {
                        Haptics.tap(.light)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove this edge from the source note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Synthetic edges (tag / embed extractors, dangling placeholders)
    /// don't have a literal `key:: [[target]]` line to rewrite —
    /// they're derived from `#tag` or `![[file]]` references. The
    /// editor would correctly refuse those, but it's cleaner to hide
    /// the affordances upfront.
    func isSynthetic(_ edge: Edge) -> Bool {
        if edge.isSynthetic { return true }
        return store.graph.nodes[edge.targetID]?.isSynthetic == true
    }

    /// Tappable relationship pill. Menu offers the atlas's known
    /// edge labels (mined from existing edges in the graph), a
    /// "Clear" affordance, and a "Custom…" route via an alert.
    @ViewBuilder
    func edgeRelationshipMenu(edge: Edge) -> some View {
        Menu {
            ForEach(knownRelationshipTypes(), id: \.self) { rel in
                Button {
                    apply(newRel: rel, to: edge)
                } label: {
                    if rel.lowercased() == (edge.relationshipType ?? "").lowercased() {
                        Label(rel, systemImage: "checkmark")
                    } else {
                        Text(rel)
                    }
                }
            }
            if edge.relationshipType != nil {
                Divider()
                Button(role: .destructive) {
                    apply(newRel: nil, to: edge)
                } label: {
                    Label("Clear", systemImage: "minus.circle")
                }
            }
        } label: {
            if let rel = edge.relationshipType {
                Text(rel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "plus").font(.caption2)
                    Text("type").font(.caption2)
                }
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.secondary.opacity(0.10), in: Capsule())
                .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    func apply(newRel: String?, to edge: Edge) {
        if let err = store.setEdgeRelationship(edge, to: newRel) {
            store.loadStatus = err
        } else {
            Haptics.tap(.light)
        }
    }

    /// Union of every relationship type already present in the
    /// graph (sorted, case-folded-deduped). Used as menu options
    /// for the relationship pill.
    func knownRelationshipTypes() -> [String] {
        var seen: [String: String] = [:]   // lowercased → original casing
        for e in store.graph.edges {
            guard let rel = e.relationshipType, !rel.isEmpty else { continue }
            if e.isSynthetic { continue }
            let key = rel.lowercased()
            if seen[key] == nil { seen[key] = rel }
        }
        return seen.values.sorted { $0.lowercased() < $1.lowercased() }
    }
}
