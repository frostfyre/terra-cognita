import SwiftUI

/// Two-pane modal for the Capture flow:
///   1. **Input pane** — text editor + on-device mic button. User types
///      or dictates a free-form note. "Process" sends it to the AI.
///   2. **Review pane** — the AI's constellation proposal as a list of
///      cards, each with type / body / link summary and an accept/reject
///      toggle. "Commit" applies the accepted subset to the atlas.
struct CaptureSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool
    /// Fires with the id of the first created node (or nil) so the
    /// canvas can frame onto it.
    var onCommitted: (String?) -> Void

    @StateObject private var intel = NodeIntelligence()
    @StateObject private var speech = SpeechRecognizer()
    @State private var inputText: String = ""
    @State private var constellation: Constellation?
    @State private var isProcessing: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if let constellation {
                    reviewPane(constellation)
                } else {
                    inputPane
                }
            }
            .navigationTitle("Capture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
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
                        Button("Process") { Task { await process() } }
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || isProcessing)
                    }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 620, minHeight: 460, idealHeight: 620)
        .task { await speech.prepare() }
        // Surface live transcript into the text field as the user speaks.
        .onChange(of: speech.transcript) { _, newValue in
            if speech.isRecording {
                inputText = newValue
            }
        }
    }

    // MARK: - Input pane

    @ViewBuilder
    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dump anything — a meeting recap, a stream of thought, a quote — and the AI will extract a graph fragment to fold into your atlas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            TextEditor(text: $inputText)
                .font(.body)
                .padding(.horizontal, 12)
                .frame(minHeight: 200)
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Tap mic to dictate, or type here…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 17)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
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

                if case .denied(let msg) = speech.availability {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if case .unsupported(let msg) = speech.availability {
                    Label(msg, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(intel.captureStatus.isEmpty ? "Working…" : intel.captureStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
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
                        Text(node.type).font(.caption).foregroundStyle(tint)
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
                FlowLayout(spacing: 4) {
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

    private func process() async {
        isProcessing = true
        defer { isProcessing = false }
        if speech.isRecording { speech.stop() }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let result = await intel.runCapture(text: text, graph: store.graph)
        if let result {
            constellation = result
            Haptics.tap(.medium)
        }
    }

    private func commit() {
        guard let constellation else { return }
        let firstID = store.applyConstellation(constellation)
        Haptics.tap(.medium)
        isPresented = false
        onCommitted(firstID)
    }
}

/// Mini flow layout — same shape as the one in NodeInspectorView so the
/// proposal chips wrap cleanly on narrow widths.
private struct FlowLayout: Layout {
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
