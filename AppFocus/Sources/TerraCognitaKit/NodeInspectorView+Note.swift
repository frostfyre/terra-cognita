import SwiftUI

/// Note disclosure: read pane (Markdown body), edit pane (TextEditor
/// with optional dictation), and the lifecycle helpers that swap
/// between them. Also hosts the diagnostic disclosure that surfaces
/// raw byte counts when a note appears empty (helps diagnose
/// encoding / GEXF issues).
extension NodeInspectorView {

    @ViewBuilder
    func noteSection(_ node: Node) -> some View {
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
    func noteReadPane(_ node: Node) -> some View {
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
                    atlasURL: store.writableAtlasURL
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
    func diagnosticInfo(body: String?, raw: String) -> some View {
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

    var noteEditPane: some View {
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
    func noteSectionLabel(_ node: Node) -> some View {
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
                      : "Open or create a writable atlas to edit.")
            }
        }
    }

    func beginNoteEdit(for node: Node) {
        noteDraft = strippedFrontMatterAndTitle(node.markdownContent ?? "")
        noteSaveError = nil
        isEditingNote = true
        showNote = true
        Task { await noteSpeech.prepare() }
    }

    /// Dispatch an externally-posted `InspectorIntent` to the right
    /// affordance. Always clears the binding so the same payload
    /// doesn't refire on the next view update.
    func consumePendingIntentIfAny(for node: Node) {
        guard let intent = pendingIntent.wrappedValue else { return }
        pendingIntent.wrappedValue = nil
        switch intent {
        case .aiOperation(let op):
            showAI = true
            ai.runOperation(op, node: node, graph: store.graph)
        case .editBody:
            guard store.canIngest else { return }
            beginNoteEdit(for: node)
        case .showMergePicker:
            guard store.canIngest else { return }
            showingMergePicker = true
        }
    }

    func cancelNoteEdit() {
        if noteSpeech.isRecording { noteSpeech.stop() }
        noteSpeech.clear()
        noteSpeechPrefix = ""
        noteDraft = ""
        noteSaveError = nil
        isEditingNote = false
    }

    func saveNoteEdit(for node: Node) {
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
    func toggleNoteDictation() {
        if noteSpeech.isRecording {
            noteSpeech.stop()
            noteSpeech.clear()
        } else {
            noteSpeechPrefix = noteDraft
            noteSpeech.clear()
            noteSpeech.start()
        }
    }
}
