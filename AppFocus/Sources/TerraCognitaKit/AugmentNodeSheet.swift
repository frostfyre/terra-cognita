import SwiftUI

/// Single sheet for *all* AI-mediated edits to an existing node.
/// Mirror of `AddNodeSheet` scoped to one bound node: free-form text
/// input + mic, an "Augment" primary button that runs the same prompt
/// pipeline against the current node (proposing body merges, new
/// wikilinks, new linked nodes, era suggestion), and quick-action
/// chips for the named single-purpose operations (Find links,
/// Suggest era, Concepts, etc.) which fire without typed input.
///
/// Shares the inspector's `NodeIntelligence` instance via
/// `@ObservedObject`, so any proposals raised here also surface in
/// the inspector's chip list after the sheet dismisses — accept /
/// reject works from either surface.
struct AugmentNodeSheet: View {
    @ObservedObject var store: GraphStore
    @ObservedObject var ai: NodeIntelligence
    @Binding var isPresented: Bool
    let node: Node

    @StateObject private var speech = SpeechRecognizer()
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    TextEditor(text: $inputText)
                        .focused($inputFocused)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if inputText.isEmpty {
                                Text("Drop context, paste a quote, or dictate. The AI will merge it into the existing body and propose links.")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 17)
                                    .padding(.top, 10)
                                    .allowsHitTesting(false)
                            }
                        }

                    HStack(spacing: 10) {
                        micButton
                        Spacer()
                        if ai.activity == .running {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)

                    if case .failed(let message) = ai.activity {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    } else if case .unavailable(let note) = ai.activity {
                        Label(note, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    quickActions

                    if !ai.proposals.isEmpty {
                        proposalsList
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Augment \"\(node.label)\"")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Augment") { runAugment() }
                        .disabled(trimmedInput.isEmpty || ai.activity == .running)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        #if os(macOS)
        // Sized for macOS sheets; on iOS the natural sheet width is
        // already correct and any minWidth ≥ ~400 bleeds buttons /
        // the editor off the right edge in portrait.
        .frame(minWidth: 500, idealWidth: 620, minHeight: 460, idealHeight: 620)
        #endif
        .task { await speech.prepare() }
        .onAppear { inputFocused = true }
        .onChange(of: speech.transcript) { _, newValue in
            if speech.isRecording {
                inputText = newValue
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Augmenting")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(node.label)
                .font(.title3.weight(.semibold))
        }
        .padding(.horizontal)
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
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick actions")
                .font(.caption)
                .foregroundStyle(.secondary)
            AugmentFlowLayout(spacing: 6) {
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
                    .disabled(ai.activity == .running || !ai.isAvailable)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var proposalsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Proposals")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(ai.proposals) { proposal in
                proposalChip(proposal)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func proposalChip(_ proposal: NodeProposal) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.summary)
                    .font(.callout)
                    .lineLimit(3)
                Text(proposal.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button {
                _ = store.applyProposal(proposal, to: node.id)
                Haptics.tap(.light)
                ai.dismissProposal(proposal.id)
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

    private func toggleRecording() {
        if speech.isRecording {
            speech.stop()
        } else {
            speech.clear()
            inputText = ""
            speech.start()
        }
    }

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runAugment() {
        if speech.isRecording { speech.stop() }
        let text = trimmedInput
        // URL-only input → fetch the page's plain text first. Mixed
        // "note + URL" inputs stay verbatim so we don't surprise the
        // user by dropping their commentary.
        if let url = urlFrom(text) {
            Task {
                let fetched = await WebEnrichment.shared.fetchText(from: url)
                let resolved = (fetched?.isEmpty == false) ? fetched! : text
                ai.runAugment(node: node, newText: resolved, graph: store.graph)
            }
            return
        }
        ai.runAugment(node: node, newText: text, graph: store.graph)
    }

    private func urlFrom(_ text: String) -> URL? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}

/// Local flow-layout copy — kept here so the augment sheet doesn't
/// reach into another file's private layout. Same shape as the one
/// in `NodeInspectorView` / `AddNodeSheet`.
private struct AugmentFlowLayout: Layout {
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
