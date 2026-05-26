import SwiftUI

/// Modal composer for creating a new node in the active vault. Used by
/// both the long-press-on-canvas flow (spatial entry) and the `+`
/// top-bar button (near-selection / center). The composer doesn't know
/// *where* the node will land — it just captures content and hands it
/// to `GraphStore.createNode`, returning the new id via `onCreated`.
struct NodeComposer: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    /// Optional id of the node the user had selected when they invoked
    /// the composer. When present, the composer pre-fills the body with
    /// a wikilink so the new node arrives already connected.
    var seedConnectionTo: String?

    /// Fires with the id of the newly-created node so the canvas can
    /// pin / frame / select it.
    var onCreated: (String) -> Void
    /// Fired when the user accepts the "Open existing instead" offer
    /// after a duplicate-label collision. The composer dismisses; the
    /// host selects the existing node.
    var onOpenExisting: (String) -> Void

    @State private var label: String = ""
    /// Current type choice — the name of a `VaultConfig.TypeSpec`.
    /// Initialized to the vault's first type on appear.
    @State private var typeChoice: String = ""
    @State private var era: String = ""
    @State private var body_: String = ""
    @State private var isPrivate: Bool = false
    @State private var errorMessage: String?
    /// Set when `submit()` returns `.duplicate(existingID:)`. Drives the
    /// "Open existing / Rename / Cancel" affordance.
    @State private var duplicateID: String?
    @FocusState private var labelFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $typeChoice) {
                        ForEach(store.config.types) { t in
                            Label(t.displayName ?? t.name.capitalized,
                                  systemImage: t.icon).tag(t.name)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Label", text: $label)
                        .focused($labelFocused)
                        .submitLabel(.next)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
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

                Section("Note") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 110)
                        .font(.body)
                    Text("Tip: link other nodes inline with [[Name]].")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let duplicateID {
                    Section {
                        Label("A node named \"\(duplicateID)\" already exists.",
                              systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        HStack {
                            Button {
                                isPresented = false
                                onOpenExisting(duplicateID)
                            } label: {
                                Label("Open existing", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Rename") {
                                self.duplicateID = nil
                                labelFocused = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Node")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: submit)
                        .disabled(trimmedLabel.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear {
                if typeChoice.isEmpty {
                    typeChoice = store.config.types.first?.name ?? "concept"
                }
                if let seed = seedConnectionTo,
                   let other = store.graph.nodes[seed],
                   body_.isEmpty {
                    body_ = "Connected to [[\(other.label)]].\n\n"
                }
                labelFocused = true
            }
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 460, idealHeight: 540)
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eraChoices: [String] { store.config.eraTagValues }

    private func submit() {
        errorMessage = nil
        duplicateID = nil
        let result = store.createNode(
            label: trimmedLabel,
            type: typeChoice,
            era: era.isEmpty ? nil : era,
            body: body_,
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
}

// Note: type vocabulary is now config-driven via VaultConfig.types.
// The old hardcoded NodeType enum was removed when custom types shipped.
