import SwiftUI

/// Phase A of the multi-pass atlas genesis flow. Lives inside
/// `TemplatePickerSheet` and replaces the single-shot description
/// field — the user has a small chat-style surface where they
/// describe the atlas they want and the AI extracts a constellation
/// of starter nodes. Single-turn for now; Phase B adds persistent
/// `LanguageModelSession` context so follow-up messages refine and
/// extend the existing constellation in-place.
///
/// The constellation is owned by the parent (binding) so it survives
/// the folder-picker round-trip in `GraphView` and commits via
/// `store.applyConstellation` after the empty atlas finishes loading.
struct AtlasGenesisChat: View {
    @ObservedObject var store: GraphStore
    /// Working constellation across turns. Empty / `nil` until the
    /// first AI extraction. The parent picker commits via
    /// `applyConstellation` after the empty atlas loads.
    @Binding var constellation: Constellation?

    @StateObject private var intel = NodeIntelligence()
    @StateObject private var speech = SpeechRecognizer()
    @State private var input: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isThinking: Bool = false
    @State private var deepeningNodeID: UUID?
    @FocusState private var inputFocused: Bool

    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        enum Role: Equatable { case user, assistant, system }
        let role: Role
        let content: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // Show availability up front (above the chat history) so
            // the user knows whether the AI is ready to extract.
            // Previously this only rendered below the input — easy
            // to miss when "got nothing" landed.
            if let availability = intel.availabilityNote, !intel.isAvailable {
                Label(availability, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .background(.orange.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 6))
            }
            if !messages.isEmpty {
                transcript
            }
            if let c = constellation, !c.nodes.isEmpty {
                constellationPreview(c)
                    .id("constellation")
            }
            inputRow
        }
        // `.submitScope()` keeps Return inside this chat. Without it,
        // hitting Return in the input also fires the parent sheet's
        // `.confirmationAction` toolbar button (Continue), so the
        // user's "send a message" gesture would *also* commit the
        // atlas — sheet dismisses, folder picker opens, user is back
        // at the canvas in one keystroke.
        .submitScope()
        .task { await speech.prepare() }
        .onChange(of: speech.transcript) { _, newValue in
            if speech.isRecording {
                input = newValue
            }
        }
        .sheet(item: deepenSheetBinding) { id in
            AtlasGenesisDeepenSheet(
                store: store,
                intel: intel,
                isPresented: Binding(
                    get: { deepeningNodeID != nil },
                    set: { newValue in
                        if !newValue { deepeningNodeID = nil }
                    }
                ),
                nodeID: id.id,
                constellation: $constellation
            )
        }
    }

    /// Identifiable wrapper so SwiftUI's `.sheet(item:)` can present
    /// against `deepeningNodeID`. Lets us use the same binding form
    /// the rest of the app uses for sheets while keeping the actual
    /// state as a plain optional.
    private struct DeepenTarget: Identifiable {
        let id: UUID
    }

    private var deepenSheetBinding: Binding<DeepenTarget?> {
        Binding(
            get: {
                deepeningNodeID.map(DeepenTarget.init)
            },
            set: { newValue in
                deepeningNodeID = newValue?.id
            }
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text("Atlas Genesis")
                .font(.headline)
            Spacer()
            if isThinking {
                ProgressView().controlSize(.small)
                Text("Extracting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Text("Describe what this atlas is about. The AI will propose a starter constellation you can grow before the atlas is even created.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var transcript: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages) { message in
                messageBubble(message)
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 24)
                Text(message.content)
                    .font(.callout)
                    .padding(8)
                    .background(.blue.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        case .assistant:
            HStack {
                Text(message.content)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.purple.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                Spacer(minLength: 24)
            }
        case .system:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func constellationPreview(_ c: Constellation) -> some View {
        let ordered = orderedNodes(c)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.cross")
                    .foregroundStyle(.tint)
                Text("Proposed constellation")
                    .font(.headline)
                Text("\(c.acceptedCount) / \(c.nodes.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Tap to toggle · ⤵ to deepen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(ordered, id: \.0.id) { node, depth in
                proposedNodeRow(node, depth: depth, in: c)
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    /// Build a depth-first ordering where children appear directly
    /// under their parent. Top-level nodes (`parentLabel == nil`)
    /// keep their original relative order; each parent's children
    /// follow in original order; recursion preserves insertion
    /// order at each layer.
    private func orderedNodes(_ c: Constellation)
        -> [(Constellation.NewNode, Int)]
    {
        var childrenByParent: [String: [Constellation.NewNode]] = [:]
        var topLevel: [Constellation.NewNode] = []
        for n in c.nodes {
            if let p = n.parentLabel {
                childrenByParent[p.lowercased(), default: []].append(n)
            } else {
                topLevel.append(n)
            }
        }
        var out: [(Constellation.NewNode, Int)] = []
        func emit(_ node: Constellation.NewNode, depth: Int) {
            out.append((node, depth))
            for child in childrenByParent[node.label.lowercased()] ?? [] {
                emit(child, depth: depth + 1)
            }
        }
        for n in topLevel { emit(n, depth: 0) }
        return out
    }

    @ViewBuilder
    private func proposedNodeRow(
        _ node: Constellation.NewNode,
        depth: Int,
        in c: Constellation
    ) -> some View {
        let tint = store.config.typeSpec(named: node.type)?.color ?? .secondary
        let childCount = c.nodes.filter {
            $0.parentLabel?.lowercased() == node.label.lowercased()
        }.count
        HStack(alignment: .top, spacing: 8) {
            if depth > 0 {
                // Visual indent + breadcrumb glyph so children read
                // as belonging to the parent above them.
                HStack(spacing: 4) {
                    ForEach(0..<depth, id: \.self) { _ in
                        Color.clear.frame(width: 10)
                    }
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            Image(systemName: node.accepted
                  ? "checkmark.circle.fill"
                  : "circle")
                .foregroundStyle(node.accepted ? tint : .secondary)
                .font(.title3)
                .padding(.top, 1)
                .contentShape(Rectangle())
                .onTapGesture { toggleAccepted(node.id) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.label).font(.callout.weight(.medium))
                    Text(node.type)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                    if let rel = node.parentRelationshipType,
                       !rel.isEmpty {
                        Text(rel)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.teal.opacity(0.15),
                                        in: Capsule())
                            .foregroundStyle(.teal)
                    }
                    if let era = node.era, !era.isEmpty {
                        Text(era)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if childCount > 0 {
                        Text("\(childCount) ↓")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.15),
                                        in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }
                if !node.body.isEmpty {
                    Text(node.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if !node.linksToExisting.isEmpty || !node.linksToNew.isEmpty {
                    let allLinks = node.linksToExisting + node.linksToNew
                    Text("→ " + allLinks.prefix(4).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.teal)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Deepen affordance — sub-constellation expansion. Runs
            // a second AI pass scoped to this node and merges the
            // proposed children + refined body via a modal sheet.
            Button {
                deepeningNodeID = node.id
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.body)
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .help("Go deeper on this node")
            .disabled(!intel.isAvailable || isThinking)
        }
        .padding(.vertical, 4)
        .opacity(node.accepted ? 1.0 : 0.45)
    }

    /// Flip a single proposed node's `accepted` flag. `applyConstellation`
    /// only commits accepted nodes, so this is what the user uses to
    /// shape the constellation before atlas creation.
    private func toggleAccepted(_ id: UUID) {
        guard var c = constellation,
              let idx = c.nodes.firstIndex(where: { $0.id == id })
        else { return }
        c.nodes[idx].accepted.toggle()
        constellation = c
    }

    @ViewBuilder
    private var inputRow: some View {
        HStack(spacing: 8) {
            micButton
            TextField(messages.isEmpty
                      ? "Describe what this atlas is about…"
                      : "Refine or expand…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($inputFocused)
                // No .onSubmit — Return inserts a newline (standard
                // multi-line behavior). The explicit Send button (or
                // ⌘↩) is the only submit path, so Return can't
                // accidentally fire the parent's Continue toolbar
                // action even if `.submitScope()` above ever fails
                // to catch it on some platform.
                .submitLabel(.return)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || isThinking
                      || !intel.isAvailable)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder
    private var micButton: some View {
        Button {
            if speech.isRecording {
                speech.stop()
            } else {
                speech.clear()
                input = ""
                speech.start()
            }
        } label: {
            Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                .font(.callout)
                .padding(8)
                .background((speech.isRecording ? Color.red : Color.purple)
                    .opacity(0.85),
                            in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(speech.availability != .ready)
    }

    private func send() {
        if speech.isRecording { speech.stop() }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        input = ""
        // Explicit @MainActor Task — runCapture / state writes /
        // binding writes all need to stay on the main actor. Without
        // it the inherited isolation can cross actor boundaries and
        // the post-extraction state writes either get lost or land
        // out of order with SwiftUI's render cycle.
        Task { @MainActor in
            await runTurn(prompt: text)
        }
    }

    /// One AI turn. Phase A: each turn runs a fresh `runCapture` —
    /// proposals from this turn *replace* the working constellation
    /// rather than extending it. Phase B will keep a `LanguageModelSession`
    /// alive and extend in-place; until then, simpler semantics keep
    /// the user from being surprised by accumulated leftovers.
    private func runTurn(prompt: String) async {
        isThinking = true
        defer { isThinking = false }

        // Build a richer prompt with the running context so even
        // single-shot capture reads as a continuation rather than
        // an isolated extraction. Phase B replaces this string-
        // smashed context with proper session memory.
        let composed = composedPrompt(latest: prompt)
        // Critical: the user is building a *new* atlas, not adding
        // to the current one. Passing `store.graph` would let the
        // AI propose `linksToExisting` against labels from the
        // currently-loaded atlas — those targets won't exist in
        // the freshly-created atlas and the user just sees
        // confusing proposals drawn from an unrelated dataset.
        // Hand the model an empty graph so the constellation is
        // self-contained and references only its own new nodes.
        let emptyGraph = Graph(nodes: [:], edges: [])
        guard let result = await intel.runCapture(
            text: composed,
            graph: emptyGraph
        ) else {
            let note: String = {
                switch intel.activity {
                case .failed(let msg): return "Sorry — \(msg)"
                case .unavailable(let msg): return msg
                default: return "Couldn't extract anything from that. Try rephrasing?"
                }
            }()
            messages.append(ChatMessage(role: .assistant, content: note))
            return
        }
        constellation = result
        let summary = summarize(result)
        messages.append(ChatMessage(role: .assistant, content: summary))
    }

    /// Compose the full context the AI sees for this turn — the
    /// running user/assistant transcript plus the latest message.
    /// Lets single-shot extraction behave like a conversation even
    /// before the persistent-session refactor in Phase B.
    private func composedPrompt(latest: String) -> String {
        var parts: [String] = []
        for m in messages.dropLast() {
            switch m.role {
            case .user: parts.append("User: \(m.content)")
            case .assistant: parts.append("Assistant: \(m.content)")
            case .system: continue
            }
        }
        parts.append("User: \(latest)")
        if let c = constellation, !c.nodes.isEmpty {
            let labels = c.nodes.prefix(20).map(\.label).joined(separator: ", ")
            parts.append("Current constellation (extend or refine, don't restart): \(labels)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func summarize(_ c: Constellation) -> String {
        guard !c.nodes.isEmpty else {
            return "I didn't find anything to extract — try giving me more to work with."
        }
        let preview = c.nodes.prefix(4).map(\.label).joined(separator: ", ")
        let more = c.nodes.count > 4
            ? ", and \(c.nodes.count - 4) more"
            : ""
        return "I extracted \(c.nodes.count) nodes (\(preview)\(more)). Tell me more, or hit Continue to create the atlas."
    }
}
