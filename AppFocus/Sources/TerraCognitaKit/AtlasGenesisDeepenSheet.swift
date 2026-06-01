import SwiftUI

/// Phase C of Atlas Genesis — modal sheet for "go deeper on this
/// node." Shows the node being deepened, the AI's proposed refined
/// body (editable), and a list of proposed children with per-child
/// accept/reject toggles. Commit replaces the parent's body and
/// appends the accepted children to the working constellation with
/// `parentLabel` set, so the chat preview can indent them under
/// their parent and the eventual `applyConstellation` can wire
/// parent→child edges with the AI-proposed relationshipType.
struct AtlasGenesisDeepenSheet: View {
    @ObservedObject var store: GraphStore
    @ObservedObject var intel: NodeIntelligence
    @Binding var isPresented: Bool
    /// Which node we're deepening — passed by id rather than value
    /// so this sheet always re-reads the current state from the
    /// working constellation.
    let nodeID: UUID
    @Binding var constellation: Constellation?

    @State private var refinedBody: String = ""
    @State private var proposedChildren: [Constellation.NewNode] = []
    @State private var didLoad = false
    @State private var keepBodyEdit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let node = currentNode {
                        header(node)
                        if intel.activity == .running {
                            workingIndicator
                        } else if case .failed(let msg) = intel.activity {
                            failedBanner(msg)
                        } else if case .unavailable(let msg) = intel.activity {
                            unavailableBanner(msg)
                        } else if proposedChildren.isEmpty
                                    && refinedBody.isEmpty {
                            emptyStateBanner
                        } else {
                            refinedBodySection
                            childrenSection
                        }
                    } else {
                        Text("Node no longer in the constellation.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Go deeper")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620,
               minHeight: 520, idealHeight: 680)
        #endif
        .task {
            // Kick the AI once on first appearance. Re-opening for
            // the same node re-runs (the user may want a different
            // angle); we could cache, but a fresh take per session
            // matches the chat metaphor better.
            guard !didLoad, let node = currentNode else { return }
            didLoad = true
            await runDeepen(for: node)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isPresented = false }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Apply") { apply() }
                .disabled(intel.activity == .running
                          || (refinedBody.isEmpty
                              && acceptedChildCount == 0))
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder
    private func header(_ node: Constellation.NewNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Deepening")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(typeTint(node.type))
                    .frame(width: 10, height: 10)
                Text(node.label)
                    .font(.title3.weight(.semibold))
                Text(node.type)
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(typeTint(node.type).opacity(0.15),
                                in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var workingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(intel.captureStatus.isEmpty
                 ? "Thinking…"
                 : intel.captureStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func failedBanner(_ msg: String) -> some View {
        Label(msg, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(8)
            .background(.red.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func unavailableBanner(_ msg: String) -> some View {
        Label(msg, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(8)
            .background(.orange.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var emptyStateBanner: some View {
        Text("Nothing came back from the model. Try a different node or rephrase the parent body.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var refinedBodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.tint)
                Text("Refined body")
                    .font(.headline)
                Spacer()
                if !refinedBody.isEmpty {
                    Toggle("Keep edits", isOn: $keepBodyEdit)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("If off, Apply leaves the current body unchanged.")
                }
            }
            TextEditor(text: $refinedBody)
                .font(.body)
                .frame(minHeight: 180)
                .padding(8)
                .background(.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .disabled(!keepBodyEdit)
                .opacity(keepBodyEdit ? 1.0 : 0.65)
        }
    }

    @ViewBuilder
    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.tint)
                Text("Proposed children")
                    .font(.headline)
                Text("\(acceptedChildCount) / \(proposedChildren.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            if proposedChildren.isEmpty {
                Text("No children proposed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($proposedChildren) { $child in
                    childRow($child)
                        .contentShape(Rectangle())
                        .onTapGesture { child.accepted.toggle() }
                }
            }
        }
    }

    @ViewBuilder
    private func childRow(_ child: Binding<Constellation.NewNode>) -> some View {
        let node = child.wrappedValue
        let tint = typeTint(node.type)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: node.accepted
                  ? "checkmark.circle.fill"
                  : "circle")
                .foregroundStyle(node.accepted ? tint : .secondary)
                .font(.title3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.label).font(.callout.weight(.medium))
                    Text(node.type)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(tint.opacity(0.15), in: Capsule())
                    if let rel = node.parentRelationshipType,
                       !rel.isEmpty {
                        Text(rel)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.teal.opacity(0.15), in: Capsule())
                            .foregroundStyle(.teal)
                    }
                    if let era = node.era, !era.isEmpty {
                        Text(era)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !node.body.isEmpty {
                    Text(node.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if !node.linksToExisting.isEmpty {
                    Text("→ " + node.linksToExisting.prefix(4)
                        .joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.teal)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(node.accepted ? 1.0 : 0.45)
    }

    // MARK: - Actions

    private func runDeepen(for node: Constellation.NewNode) async {
        guard let ctx = constellation else { return }
        let result = await intel.runDeepen(node: node, context: ctx)
        guard let (body, children) = result else {
            refinedBody = ""
            proposedChildren = []
            return
        }
        refinedBody = body
        proposedChildren = children
        // Default the body-edit toggle on if the AI returned a body
        // that differs meaningfully from the current one. Otherwise
        // off — we don't want to surprise the user by silently
        // overwriting bodies they liked.
        let oldBody = node.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let newBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        keepBodyEdit = !newBody.isEmpty && newBody != oldBody
    }

    private func apply() {
        guard var c = constellation else { return }
        guard let idx = c.nodes.firstIndex(where: { $0.id == nodeID })
        else { return }

        // (1) Refined body if the user kept it.
        if keepBodyEdit {
            let trimmed = refinedBody
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                c.nodes[idx].body = refinedBody
            }
        }

        // (2) Append accepted children with parentLabel preserved.
        let accepted = proposedChildren.filter { $0.accepted }
        c.nodes.append(contentsOf: accepted)
        constellation = c
        Haptics.tap(.medium)
        isPresented = false
    }

    // MARK: - Helpers

    private var currentNode: Constellation.NewNode? {
        constellation?.nodes.first(where: { $0.id == nodeID })
    }

    private var acceptedChildCount: Int {
        proposedChildren.filter { $0.accepted }.count
    }

    private func typeTint(_ type: String) -> Color {
        store.config.typeSpec(named: type)?.color ?? .secondary
    }
}
