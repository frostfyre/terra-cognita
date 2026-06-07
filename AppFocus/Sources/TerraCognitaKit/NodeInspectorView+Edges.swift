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
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.secondary.opacity(0.20), in: Capsule())
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
                    .foregroundColor(.primary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.secondary.opacity(0.20), in: Capsule())
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "plus").font(.caption2).foregroundColor(.primary)
                    Text("type").font(.caption2).foregroundColor(.primary)
                }
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.secondary.opacity(0.20), in: Capsule())
            }
        }
        .menuStyle(.borderlessButton)
        .tint(.primary)
        .fixedSize()
    }

    func apply(newRel: String?, to edge: Edge) {
        if let err = store.setEdgeRelationship(edge, to: newRel) {
            store.loadStatus = err
        } else {
            Haptics.tap(.light)
        }
    }

    /// Section label for Outbound / Inbound that adds an inline
    /// `+` pill on the right for "add a new link in this direction."
    /// The pill opens a `NodeSearchView` sheet so the user can pick
    /// a target by search — complements the spatial Connect mode on
    /// the canvas with a list-based route that's contextual to the
    /// node already being inspected.
    @ViewBuilder
    func edgeSectionLabel(_ title: String,
                          count: Int,
                          direction: NodeInspectorView.AddLinkDirection) -> some View {
        HStack(spacing: 6) {
            sectionLabel(title, count: count)
            if store.canIngest {
                Button {
                    addingLink = direction
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(direction == .outbound
                      ? "Add an outbound link"
                      : "Add an inbound link from another node")
            }
        }
    }

    /// Search-picker sheet for "add a link in `direction`." Outbound
    /// → pick a target, create `current → picked`. Inbound → pick a
    /// source, create `picked → current` (writes to the picked
    /// node's body, not the current one). Duplicates and self-links
    /// surface via the dismissable status pill, same as the spatial
    /// Connect path.
    @ViewBuilder
    func addLinkPickerSheet(direction: NodeInspectorView.AddLinkDirection) -> some View {
        let prompt = direction == .outbound
            ? "Pick a node to link to"
            : "Pick a node to link from"
        VStack(spacing: 10) {
            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            NodeSearchView(store: store) { chosen in
                guard let other = chosen else {
                    addingLink = nil
                    return
                }
                let from = direction == .outbound ? nodeID : other
                let to = direction == .outbound ? other : nodeID
                if let err = store.createEdge(from: from, to: to) {
                    store.loadStatus = err
                } else if let target = store.graph.nodes[to] {
                    store.loadStatus = "Linked → \(target.label)"
                }
                addingLink = nil
            }
            Spacer()
        }
        .padding(.bottom, 12)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 360, idealHeight: 420)
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
