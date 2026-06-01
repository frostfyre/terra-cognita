import SwiftUI

/// Single sheet for *all* node-creation paths. Replaces the previous
/// `NodeComposer` + `CaptureSheet` pair, which split the same intent
/// across two surfaces:
///
///   - `NodeComposer` — manual fields (label / type / era / body)
///   - `CaptureSheet` — free-form text → AI-extracted constellation
///
/// The merged sheet has one adaptive input. Short label-like text saves
/// a placeholder via `createNode`; longer text (or pasted URLs, when
/// fetch lands) runs through the existing `NodeIntelligence.runCapture`
/// constellation flow. The user never picks the mode — the input shape
/// picks it. A live hint under the field tells them which path will run.
///
/// Optional `Details` disclosure exposes the type / era / private
/// toggles, hidden by default so the placeholder path is one tap.
struct AddNodeSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    /// Optional id of the node the user had selected when they invoked
    /// the sheet. The placeholder body is pre-seeded with a wikilink so
    /// the new node arrives already connected. The constellation path
    /// doesn't use the seed (the AI builds its own link graph).
    var seedConnectionTo: String?

    /// World point captured by the radial / canvas tap so the new node
    /// can land there. `nil` lets the canvas pick a position. Only
    /// applies to the placeholder path — constellation members get
    /// FA2-laid-out positions.
    var spawnWorld: CGPoint?

    /// Fired with the id of the first created node (placeholder) or
    /// first accepted constellation node, so the host can frame and
    /// select it.
    var onCreated: (String) -> Void
    /// Fired when the user accepts "Open existing" after a duplicate
    /// collision on the placeholder path. The sheet dismisses; the
    /// host selects the existing node.
    var onOpenExisting: (String) -> Void

    @StateObject private var intel = NodeIntelligence()
    @StateObject private var speech = SpeechRecognizer()
    @State private var inputText: String = ""
    @State private var typeChoice: String = ""
    @State private var era: String = ""
    @State private var isPrivate: Bool = false
    @State private var showDetails: Bool = false
    @State private var constellation: Constellation?
    @State private var isProcessing: Bool = false
    @State private var duplicateID: String?
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let constellation {
                    reviewPane(constellation)
                } else {
                    inputPane
                }
            }
            .navigationTitle("Add Node")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        #if os(macOS)
        // The minWidth was sized for macOS sheets. Applying it on
        // iOS pushes the content past the screen edges in portrait
        // (typically 375–428pt wide), bleeding buttons and the
        // editor off the right. Let iOS use the natural sheet width.
        .frame(minWidth: 500, idealWidth: 620, minHeight: 460, idealHeight: 620)
        #endif
        .task { await speech.prepare() }
        .onAppear {
            if typeChoice.isEmpty {
                typeChoice = store.config.types.first?.name ?? "concept"
            }
            inputFocused = true
        }
        .onChange(of: speech.transcript) { _, newValue in
            if speech.isRecording {
                inputText = newValue
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isPresented = false }
        }
        if constellation != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Commit") { commit() }
                    .disabled(constellation?.acceptedCount == 0)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button(primaryActionLabel) { Task { await runPrimary() } }
                    .disabled(trimmedInput.isEmpty || isProcessing)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Input pane

    @ViewBuilder
    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type a label for a placeholder, or paste a paragraph for the AI to extract a constellation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            TextEditor(text: $inputText)
                .focused($inputFocused)
                .font(.body)
                .padding(.horizontal, 12)
                .frame(minHeight: 180)
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Tap mic to dictate, or type here…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 17)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                }

            modeHintRow

            HStack(spacing: 10) {
                micButton
                if case .denied(let msg) = speech.availability {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else if case .unsupported(let msg) = speech.availability {
                    Label(msg, systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(intel.captureStatus.isEmpty ? "Working…" : intel.captureStatus)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            detailsDisclosure

            if let duplicateID {
                duplicateBanner(duplicateID)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.bottom, 8)
        // Explicit width cap so any inner control with a large
        // idealWidth (segmented Picker with many options, very long
        // label text, etc.) can't drag the leading-aligned VStack
        // past the iPhone's portrait width and clip the children at
        // both edges.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var modeHintRow: some View {
        if !trimmedInput.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: modeHintIcon)
                    .foregroundStyle(isComplexInput ? .purple : .secondary)
                Text(modeHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private var modeHintIcon: String {
        if urlFrom(trimmedInput) != nil { return "globe" }
        return isComplexInput ? "sparkles" : "circle.dashed"
    }

    private var modeHintText: String {
        if urlFrom(trimmedInput) != nil {
            return "Will fetch the page and let the AI extract a constellation."
        }
        return isComplexInput
            ? "AI will extract a constellation."
            : "Will save as a placeholder you can flesh out later."
    }

    @ViewBuilder
    private var micButton: some View {
        Button {
            toggleRecording()
        } label: {
            Label(speech.isRecording ? "Stop" : "Dictate",
                  systemImage: speech.isRecording ? "stop.fill" : "mic.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background((speech.isRecording ? Color.red : Color.purple).opacity(0.85),
                            in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(speech.availability != .ready)
    }

    @ViewBuilder
    private var detailsDisclosure: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: $typeChoice) {
                    ForEach(store.config.types) { t in
                        Label(t.displayName ?? t.name.capitalized,
                              systemImage: t.icon).tag(t.name)
                    }
                }
                // Segmented packs many options into one row — its
                // idealWidth scales with the number of types and on
                // iPhone (≤ ~430pt portrait) easily exceeds the sheet
                // width, dragging the leading-aligned content past
                // both edges. .menu collapses to a single button on
                // iOS while keeping the segmented affordance on the
                // roomier macOS/iPad surfaces.
                #if os(iOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.segmented)
                #endif

                Picker("Era", selection: $era) {
                    Text("—").tag("")
                    ForEach(eraChoices, id: \.self) { e in
                        Text(e).tag(e)
                    }
                }

                Toggle(isOn: $isPrivate) {
                    Label("Private", systemImage: "eye.slash")
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Details (type, era, private)",
                  systemImage: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func duplicateBanner(_ existingID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("A node named \"\(existingID)\" already exists.",
                  systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.orange)
            HStack {
                Button {
                    isPresented = false
                    onOpenExisting(existingID)
                } label: {
                    Label("Open existing", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                Button("Rename") {
                    duplicateID = nil
                    inputFocused = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    private func toggleRecording() {
        if speech.isRecording {
            speech.stop()
        } else {
            speech.clear()
            inputText = ""
            speech.start()
        }
    }

    // MARK: - Review pane

    @ViewBuilder
    private func reviewPane(_ constellation: Constellation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap a card to toggle acceptance. The accepted nodes will be created and linked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(constellation.nodes) { node in
                    nodeCard(node)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func nodeCard(_ node: Constellation.NewNode) -> some View {
        let tint = typeTint(node.type)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: node.accepted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(node.accepted ? tint : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.label).font(.headline)
                    HStack(spacing: 6) {
                        Text(node.type)
                            .font(.caption)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(tint.opacity(0.15), in: Capsule())
                        if let era = node.era, !era.isEmpty {
                            Text("· \(era)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if node.enrichmentTitle != nil {
                            Label("Wikipedia", systemImage: "globe")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.blue.opacity(0.18), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
                Spacer()
            }
            if !node.body.isEmpty {
                Text(node.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if !node.linksToNew.isEmpty || !node.linksToExisting.isEmpty {
                AddNodeFlowLayout(spacing: 4) {
                    ForEach(node.linksToNew, id: \.self) { other in
                        linkChip(other, isInternal: true)
                    }
                    ForEach(node.linksToExisting, id: \.self) { other in
                        linkChip(other, isInternal: false)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(node.accepted ? 0.10 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(node.accepted ? tint.opacity(0.5) : .secondary.opacity(0.2),
                        lineWidth: node.accepted ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggleAcceptance(node.id) }
    }

    @ViewBuilder
    private func linkChip(_ label: String, isInternal: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: isInternal ? "sparkles" : "link")
                .font(.caption2)
            Text(label).font(.caption2).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background((isInternal ? Color.purple : Color.teal).opacity(0.15), in: Capsule())
        .foregroundStyle(isInternal ? .purple : .teal)
    }

    private func typeTint(_ type: String) -> Color {
        store.config.typeSpec(named: type)?.color ?? .secondary
    }

    private func toggleAcceptance(_ id: UUID) {
        guard var c = constellation,
              let idx = c.nodes.firstIndex(where: { $0.id == id }) else { return }
        c.nodes[idx].accepted.toggle()
        constellation = c
        Haptics.tap(.light)
    }

    // MARK: - Actions

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eraChoices: [String] { store.config.eraTagValues }

    /// Heuristic that decides the mode for the primary button. Anything
    /// label-shaped (single line, ≤80 chars, no URL) saves a placeholder;
    /// anything that looks like a paragraph or URL runs the constellation
    /// extraction.
    private var isComplexInput: Bool {
        let t = trimmedInput
        if t.contains("\n") { return true }
        if t.count > 80 { return true }
        // Rough URL sniff — avoids URL() / NSDataDetector overhead.
        if t.lowercased().contains("http://") || t.lowercased().contains("https://") {
            return true
        }
        return false
    }

    private var primaryActionLabel: String {
        isComplexInput ? "Process" : "Add"
    }

    private func runPrimary() async {
        if speech.isRecording { speech.stop() }
        if isComplexInput {
            await processCapture()
        } else {
            submitPlaceholder()
        }
    }

    private func processCapture() async {
        isProcessing = true
        defer { isProcessing = false }
        let text = trimmedInput
        guard !text.isEmpty else { return }
        // URL-only input → fetch the page's plain text and use that as
        // the source for the AI. Frees the user from having to copy a
        // Wikipedia / article paragraph into the box.
        let sourceText: String
        if let url = urlFrom(text),
           let fetched = await WebEnrichment.shared.fetchText(from: url),
           !fetched.isEmpty {
            sourceText = fetched
        } else {
            sourceText = text
        }
        let result = await intel.runCapture(text: sourceText, graph: store.graph)
        if let result {
            constellation = result
            Haptics.tap(.medium)
        }
    }

    /// Returns the URL if `text` is a single http(s) URL with no other
    /// content. We only fetch when the user pasted a bare link — mixed
    /// "here's my idea: https://…" inputs stay text-as-typed.
    private func urlFrom(_ text: String) -> URL? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    private func submitPlaceholder() {
        errorMessage = nil
        duplicateID = nil
        let label = trimmedInput
        let body: String
        if let seed = seedConnectionTo,
           let other = store.graph.nodes[seed] {
            body = "Connected to [[\(other.label)]].\n\n"
        } else {
            body = ""
        }
        let result = store.createNode(
            label: label,
            type: typeChoice,
            era: era.isEmpty ? nil : era,
            body: body,
            isPrivate: isPrivate
        )
        switch result {
        case .success(let id):
            Haptics.tap(.medium)
            isPresented = false
            onCreated(id)
        case .failure(.duplicate(let existingID)):
            duplicateID = existingID
        case .failure(let err):
            errorMessage = err.errorDescription ?? "Something went wrong."
        }
    }

    private func commit() {
        guard let constellation else { return }
        let firstID = store.applyConstellation(constellation)
        Haptics.tap(.medium)
        isPresented = false
        if let firstID { onCreated(firstID) }
    }
}

/// Mini flow layout for the constellation review chips. Same shape as
/// the one previously in `CaptureSheet` and `NodeInspectorView`; lives
/// here so the merged sheet doesn't need either of its predecessors.
private struct AddNodeFlowLayout: Layout {
    var spacing: CGFloat = 4

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
