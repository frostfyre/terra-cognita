import SwiftUI

/// AI section of the inspector — Operations row, Proposals list,
/// message transcript, free-form follow-up, and the "explain
/// connection" suggestion chips for direct neighbours. The
/// `NodeIntelligence` instance lives on the inspector struct; this
/// extension just renders against it.
extension NodeInspectorView {

    @ViewBuilder
    func aiSection(_ node: Node) -> some View {
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
                        InspectorFlowLayout(spacing: 6) {
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
    func operationsRow(_ node: Node) -> some View {
        Button {
            showingAugmentSheet = true
        } label: {
            Label("Augment this node…", systemImage: "wand.and.sparkles")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.purple)
        }
        .buttonStyle(.plain)
        .disabled(ai.activity == .running)
    }

    @ViewBuilder
    func proposalsList(_ node: Node) -> some View {
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

    func proposalChip(_ proposal: NodeProposal, node: Node) -> some View {
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

    func sendFollowup() {
        let q = followupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let node = store.graph.nodes[nodeID] else { return }
        ai.ask(q, currentNode: node)
        followupDraft = ""
    }

    @ViewBuilder
    func messageBubble(_ message: NodeIntelligence.Message) -> some View {
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
}
