import SwiftUI

/// Top of the inspector: title, type / era pills, Summarize button,
/// Open-in-default-app, and the more-actions menu (Merge / Delete).
/// Also hosts the merge picker sheet and the type / era pickers
/// they both depend on.
extension NodeInspectorView {

    func header(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.label)
                .font(.title2).bold()
                .textSelection(.enabled)
            HStack(spacing: 6) {
                typePicker(node)
                eraPicker(node)
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

                Spacer()
                Menu {
                    Button {
                        showingMergePicker = true
                    } label: {
                        Label("Merge into…", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(!store.canIngest)
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete this node", systemImage: "trash")
                    }
                    .disabled(!store.canIngest)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More actions")
            }
        }
        .alert("Delete \"\(node.label)\"?",
               isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let err = store.deleteNode(node.id) {
                    print("deleteNode failed: \(err)")
                } else {
                    onSelectNode(nil)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the .md file (a .bak snapshot is kept). Wikilinks in other notes will become dangling.")
        }
        .sheet(isPresented: $showingMergePicker) {
            mergePickerSheet(losingNode: node)
        }
    }

    @ViewBuilder
    func mergePickerSheet(losingNode: Node) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Pick a node to merge into…", text: $mergePickerQuery)
                        .textFieldStyle(.plain)
                }
                .padding()
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(mergeCandidates(for: losingNode), id: \.id) { candidate in
                            Button {
                                if let err = store.mergeNode(losingNode.id, into: candidate.id) {
                                    print("mergeNode failed: \(err)")
                                } else {
                                    showingMergePicker = false
                                    onSelectNode(candidate.id)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if let t = candidate.type {
                                        Circle().fill(typeColor(t)).frame(width: 8, height: 8)
                                    } else {
                                        Circle().fill(.secondary).frame(width: 8, height: 8)
                                    }
                                    Text(candidate.label).lineLimit(1)
                                    Spacer()
                                    if let t = candidate.type {
                                        Text(t).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Merge \"\(losingNode.label)\" into…")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingMergePicker = false }
                }
            }
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 360, idealHeight: 480)
    }

    func mergeCandidates(for losingNode: Node) -> [Node] {
        let q = mergePickerQuery.lowercased()
        return store.graph.nodes.values
            .filter { $0.id != losingNode.id }
            .filter { q.isEmpty || $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
            .sorted { $0.label.lowercased() < $1.label.lowercased() }
            .prefix(60)
            .map { $0 }
    }

    /// Tappable type pill — opens a menu of the atlas's configured
    /// types so the user can reclassify a node without leaving the
    /// inspector. The physical file does NOT move between subfolders
    /// (would invalidate every wikilink pointing at it); only the
    /// `type:` front-matter is rewritten via
    /// `GraphStore.setType(in:to:)`. For nodes with no backing file
    /// yet, one is materialized on first set.
    @ViewBuilder
    func typePicker(_ node: Node) -> some View {
        let current = node.type?.lowercased() ?? ""
        Menu {
            ForEach(promotableTypes(), id: \.name) { spec in
                Button {
                    if let err = store.setType(in: node.id, to: spec.name) {
                        store.loadStatus = err
                    } else {
                        Haptics.tap(.light)
                    }
                } label: {
                    if spec.name.lowercased() == current {
                        Label(spec.displayName ?? spec.name.capitalized,
                              systemImage: "checkmark")
                    } else {
                        Label(spec.displayName ?? spec.name.capitalized,
                              systemImage: spec.icon)
                    }
                }
            }
        } label: {
            if let t = node.type, !t.isEmpty {
                TagPill(text: t, color: typeColor(t))
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "tag").font(.caption2)
                    Text("set type").font(.caption2)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.20), in: Capsule())
                // Explicit `.primary` — Menu labels otherwise inherit the
                // system tint (orange on this build), which against a pale
                // capsule bg goes effectively invisible.
                .foregroundStyle(.primary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!store.canIngest)
    }

    /// Tappable era pill — opens a menu with every era taxonomy value
    /// plus a "Clear" affordance. Edits write through to the .md file
    /// immediately; the depth axis updates on the next render tick.
    @ViewBuilder
    func eraPicker(_ node: Node) -> some View {
        let current = node.era ?? ""
        Menu {
            ForEach(store.config.eraTagValues, id: \.self) { value in
                Button {
                    if let err = store.setEra(in: node.id, to: value) {
                        print("setEra failed: \(err)")
                    } else {
                        Haptics.tap(.light)
                    }
                } label: {
                    if value == current {
                        Label(value, systemImage: "checkmark")
                    } else {
                        Text(value)
                    }
                }
            }
            if !current.isEmpty {
                Divider()
                Button(role: .destructive) {
                    if let err = store.setEra(in: node.id, to: nil) {
                        print("setEra clear failed: \(err)")
                    } else {
                        Haptics.tap(.light)
                    }
                } label: {
                    Label("Clear era", systemImage: "xmark.circle")
                }
            }
        } label: {
            if current.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "calendar.badge.plus").font(.caption2)
                    Text("set era").font(.caption2)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.20), in: Capsule())
                .foregroundStyle(.primary)
            } else {
                HStack(spacing: 3) {
                    Text(current).font(.caption2)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.25), in: Capsule())
                .foregroundStyle(.primary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!store.canIngest)
    }
}
