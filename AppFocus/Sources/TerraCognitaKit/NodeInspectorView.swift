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
    /// `nil` means "clear the current selection" (used after delete).
    var onSelectNode: (String?) -> Void

    @State private var showAI = true
    @State private var showMetadata = false
    @State private var showNote = true
    @State private var showOutbound = true
    @State private var showInbound = false
    @State private var followupDraft: String = ""
    @StateObject private var ai = NodeIntelligence()

    // Delete + merge confirmation state.
    @State private var showingDeleteConfirm = false
    @State private var showingMergePicker = false
    @State private var mergePickerQuery: String = ""

    // Note editing state. `isEditingNote` toggles the Note disclosure
    // between MarkdownBodyView (read) and a TextEditor (write).
    // `noteDraft` is seeded from the stripped body on entry and written
    // back via `store.updateNodeBody` on Save. `noteSpeech` provides
    // optional mic-driven dictation that appends to whatever the user
    // has already typed.
    @State private var isEditingNote = false
    @State private var noteDraft: String = ""
    @State private var noteSaveError: String?
    @State private var noteSpeechPrefix: String = ""
    @StateObject private var noteSpeech = SpeechRecognizer()

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
                    // If we're swapping nodes mid-edit, drop the draft —
                    // the user is now looking at a different note.
                    if isEditingNote { cancelNoteEdit() }
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
    private func mergePickerSheet(losingNode: Node) -> some View {
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

    private func mergeCandidates(for losingNode: Node) -> [Node] {
        let q = mergePickerQuery.lowercased()
        return store.graph.nodes.values
            .filter { $0.id != losingNode.id }
            .filter { q.isEmpty || $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
            .sorted { $0.label.lowercased() < $1.label.lowercased() }
            .prefix(60)
            .map { $0 }
    }

    /// Tappable era pill — opens a menu with every era taxonomy value
    /// plus a "Clear" affordance. Edits write through to the .md file
    /// Tappable type pill — opens a menu of the vault's configured
    /// types so the user can reclassify a node without leaving the
    /// inspector. The physical file does NOT move between subfolders
    /// (would invalidate every wikilink pointing at it); only the
    /// `type:` front-matter is rewritten via
    /// `GraphStore.setType(in:to:)`. For nodes with no backing file
    /// yet, one is materialized on first set.
    @ViewBuilder
    private func typePicker(_ node: Node) -> some View {
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
                .background(.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!store.canIngest)
    }

    /// immediately; the depth axis updates on the next render tick.
    @ViewBuilder
    private func eraPicker(_ node: Node) -> some View {
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
                .background(.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
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

            // Preset operations + their AI-proposed mutations.
            if ai.isAvailable && store.canIngest {
                operationsRow(node)
                if !ai.proposals.isEmpty {
                    proposalsList(node)
                }
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

    // MARK: - Operations row + proposal chips

    @ViewBuilder
    private func operationsRow(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Operations")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(NodeIntelligence.Operation.allCases) { op in
                    Button {
                        ai.runOperation(op, node: node, graph: store.graph)
                    } label: {
                        Label(op.rawValue, systemImage: op.icon)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.purple.opacity(0.14), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(ai.activity == .running)
                }
            }
        }
    }

    @ViewBuilder
    private func proposalsList(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Proposals")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(ai.proposals) { proposal in
                proposalChip(proposal, node: node)
            }
        }
        .padding(.top, 2)
    }

    private func proposalChip(_ proposal: NodeProposal, node: Node) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.summary)
                    .font(.callout)
                    .lineLimit(2)
                Text(proposal.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button {
                if let err = store.applyProposal(proposal, to: node.id) {
                    ai.dismissProposal(proposal.id)
                    // Re-surface via activity so the user sees it.
                    // (NodeIntelligence is the source of activity truth.)
                    print("applyProposal failed: \(err)")
                } else {
                    Haptics.tap(.light)
                    ai.dismissProposal(proposal.id)
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            Button {
                ai.dismissProposal(proposal.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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

    // MARK: - Placeholder promotion

    /// Banner shown only for synthetic placeholder nodes (created by
    /// the loader's dangling-wikilink extractor). Lets the user
    /// promote the placeholder to one of the vault's configured
    /// real types — materializes a fresh `.md` file and re-targets
    /// edges in-memory so focus survives the transition.
    @ViewBuilder
    private func placeholderPromotionBanner(_ node: Node) -> some View {
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
    private func promotableTypes() -> [VaultConfig.TypeSpec] {
        let synthetic: Set<String> = ["tag", "embed", "placeholder"]
        return store.config.types.filter {
            !synthetic.contains($0.name.lowercased())
        }
    }

    private func promoteCurrent(to typeName: String, for node: Node) {
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

    // MARK: - Note section (read + edit)

    @ViewBuilder
    private func noteSection(_ node: Node) -> some View {
        if isEditingNote {
            noteEditPane
        } else {
            noteReadPane(node)
        }
    }

    /// Read-mode body of the Note disclosure. Split out from
    /// `noteSection` so the @ViewBuilder doesn't have to juggle a
    /// `let`-binding inside its outer branch — a structure that's
    /// been observed to occasionally collapse on iOS into an empty
    /// branch.
    @ViewBuilder
    private func noteReadPane(_ node: Node) -> some View {
        if let md = node.markdownContent, !md.isEmpty {
            let body = strippedFrontMatterAndTitle(md)
            if hasRenderableProse(body) {
                MarkdownBodyView(
                    source: body,
                    onWikilinkClick: { slug in
                        if let resolved = resolveWikilink(slug) {
                            onSelectNode(resolved)
                        }
                    },
                    resolveEmbed: { filename in
                        resolveEmbed(filename, for: node)
                    },
                    vaultURL: store.writableVaultURL
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No prose body — typed edges are shown in Outbound.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    diagnosticInfo(body: body, raw: md)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No body").font(.caption).foregroundStyle(.secondary)
                diagnosticInfo(body: nil, raw: node.markdownContent ?? "")
            }
        }
    }

    /// Tiny debug strip showing what we actually have in the
    /// markdownContent / post-strip body. Helps diagnose the
    /// "renders on macOS, blank on iOS" class of bug when content
    /// arrives via GEXF / unusual encodings. Tap to expand the raw
    /// body for a deeper look.
    @ViewBuilder
    private func diagnosticInfo(body: String?, raw: String) -> some View {
        let summary = "raw \(raw.count) chars · stripped \(body?.count ?? 0) chars"
        DisclosureGroup {
            ScrollView {
                Text(raw.isEmpty ? "(empty)" : raw)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .frame(maxHeight: 200)
        } label: {
            Text(summary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var noteEditPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $noteDraft)
                .font(.body)
                .frame(minHeight: 160)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            if let err = noteSaveError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func noteSectionLabel(_ node: Node) -> some View {
        HStack(spacing: 6) {
            sectionLabel("Note")
            Spacer(minLength: 8)
            if isEditingNote {
                // Mic toggle — appends dictated text to whatever the
                // user has already typed. We snapshot the editor's
                // current text on each session start so transcript
                // updates extend it rather than replacing it.
                Button {
                    toggleNoteDictation()
                } label: {
                    Image(systemName: noteSpeech.isRecording
                          ? "mic.fill"
                          : "mic")
                        .foregroundStyle(noteSpeech.isRecording ? .red : .accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(noteSpeech.availability != .ready)
                .help(noteSpeech.isRecording ? "Stop dictation" : "Dictate")

                Button("Cancel") { cancelNoteEdit() }
                    .buttonStyle(.borderless)
                Button("Save") { saveNoteEdit(for: node) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.canIngest)
            } else {
                Button {
                    beginNoteEdit(for: node)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!store.canIngest)
                .help(store.canIngest
                      ? "Edit note"
                      : "Open or create a writable vault to edit.")
            }
        }
    }

    private func beginNoteEdit(for node: Node) {
        noteDraft = strippedFrontMatterAndTitle(node.markdownContent ?? "")
        noteSaveError = nil
        isEditingNote = true
        showNote = true
        Task { await noteSpeech.prepare() }
    }

    private func cancelNoteEdit() {
        if noteSpeech.isRecording { noteSpeech.stop() }
        noteSpeech.clear()
        noteSpeechPrefix = ""
        noteDraft = ""
        noteSaveError = nil
        isEditingNote = false
    }

    private func saveNoteEdit(for node: Node) {
        if noteSpeech.isRecording { noteSpeech.stop() }
        // Stitch the `# Title` heading back in so it round-trips —
        // the user is editing post-title body, but the file format
        // expects the heading after the front-matter.
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyWithTitle = "# \(node.label)\n\n\(trimmed)\n"
        if let err = store.updateNodeBody(node.id, body: bodyWithTitle) {
            noteSaveError = err
            return
        }
        cancelNoteEdit()
    }

    /// Toggle dictation. On start we snapshot the editor's current
    /// text so transcripts append rather than replace. On stop we
    /// commit whatever was transcribed into `noteDraft` and clear
    /// the recognizer.
    private func toggleNoteDictation() {
        if noteSpeech.isRecording {
            noteSpeech.stop()
            noteSpeech.clear()
        } else {
            noteSpeechPrefix = noteDraft
            noteSpeech.clear()
            noteSpeech.start()
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
    private func hasRenderableProse(_ body: String) -> Bool {
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

    /// Resolve an Obsidian embed reference (`sketch.png`, `subfolder/x.pdf`,
    /// etc.) to a file URL the markdown view can render. Searches:
    ///   1. The node's containing folder + relative path
    ///   2. The vault root + relative path
    ///   3. A recursive search by basename across the vault (Obsidian-style)
    /// Returns `nil` if nothing matches or no writable vault is open.
    private func resolveEmbed(_ filename: String, for node: Node) -> URL? {
        let fm = FileManager.default
        let cleaned = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // 1. Relative to the node file's directory.
        if let nodePath = node.filePath {
            let nodeDir = URL(fileURLWithPath: nodePath).deletingLastPathComponent()
            let candidate = nodeDir.appendingPathComponent(cleaned)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        // 2. Relative to the vault root.
        if let vault = store.writableVaultURL {
            let candidate = vault.appendingPathComponent(cleaned)
            if fm.fileExists(atPath: candidate.path) { return candidate }
            // 3. Recursive basename search (Obsidian doesn't require
            //    paths if the filename is unique).
            let basename = (cleaned as NSString).lastPathComponent
            if let enumerator = fm.enumerator(
                at: vault,
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
        store.config.typeSpec(named: type)?.color ?? .secondary
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
