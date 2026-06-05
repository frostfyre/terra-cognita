import SwiftUI

/// In-app editor for the atlas's `.terracognita/config.yaml`. Lets the
/// user manage their type vocabulary, era taxonomy, and extractor
/// toggles without hand-writing YAML. Saves write the config back to
/// disk; the atlas auto-reloads so the new ontology takes effect.
struct AtlasSettingsSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    @State private var draft: AtlasConfig
    @State private var errorMessage: String?

    init(store: GraphStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
        // Start from the live config; user edits build up locally
        // until they hit Save.
        self._draft = State(initialValue: store.config)
    }

    private let syntheticNames: Set<String> = ["tag", "embed", "placeholder"]

    var body: some View {
        NavigationStack {
            Form {
                typesSection
                erasSection
                extractorsSection
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Atlas Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!store.canIngest)
                }
            }
        }
        // Sizes the sheet window on macOS; on iOS the sheet is full-screen
        // and a 520pt minWidth would force the Form wider than an iPhone,
        // clipping content.
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 540, idealHeight: 680)
        #endif
    }

    // MARK: - Types

    private var typesSection: some View {
        Section {
            // Identify rows by position, not by `spec.id` (which is the
            // editable `name`). Otherwise every keystroke renames the row,
            // ForEach diffs it as new, and the focused TextField is
            // re-created — on iOS that dismisses the keyboard.
            ForEach(Array(userTypes.enumerated()), id: \.offset) { _, spec in
                typeRow(spec)
            }
            .onDelete(perform: deleteTypes)
            Button {
                addType()
            } label: {
                Label("Add type", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Types")
                Spacer()
                Text("\(userTypes.count)").foregroundStyle(.secondary)
            }
        } footer: {
            Text("Built-in synthetic types (tag / embed / placeholder) are always available and aren't shown here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func typeRow(_ spec: AtlasConfig.TypeSpec) -> some View {
        let binding = bindingForType(spec.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: binding.wrappedValue.icon)
                    .foregroundStyle(binding.wrappedValue.color)
                    .frame(width: 22)
                TextField("name", text: Binding(
                    get: { binding.wrappedValue.name },
                    set: { binding.wrappedValue.name = $0.lowercased() }
                ))
                .textFieldStyle(.roundedBorder)
                ColorPicker("", selection: binding.color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36)
            }
            HStack(spacing: 6) {
                TextField("display name (optional)",
                          text: Binding(
                            get: { binding.wrappedValue.displayName ?? "" },
                            set: { binding.wrappedValue.displayName = $0.isEmpty ? nil : $0 }
                          ))
                .textFieldStyle(.roundedBorder)
                TextField("SF Symbol",
                          text: Binding(
                            get: { binding.wrappedValue.icon },
                            set: { binding.wrappedValue.icon = $0 }
                          ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
            }
            TextField("folder (optional)",
                      text: Binding(
                        get: { binding.wrappedValue.folder ?? "" },
                        set: { binding.wrappedValue.folder = $0.isEmpty ? nil : $0 }
                      ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Eras

    private var erasSection: some View {
        Section {
            // Index-based identity for the same reason as types — `EraSpec.id`
            // is the editable name, so binding-driven ForEach would re-create
            // the row on every keystroke.
            ForEach(Array(draft.eras.indices), id: \.self) { idx in
                HStack {
                    TextField("name", text: $draft.eras[idx].name)
                        .textFieldStyle(.roundedBorder)
                    Text("weight").font(.caption2).foregroundStyle(.secondary)
                    TextField("0", value: $draft.eras[idx].weight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
            }
            .onDelete { offsets in
                draft.eras.remove(atOffsets: offsets)
            }
            .onMove { src, dst in
                draft.eras.move(fromOffsets: src, toOffset: dst)
            }
            Button {
                let nextWeight = (draft.eras.map(\.weight).max() ?? -1) + 1
                draft.eras.append(.init(name: "new-era", weight: nextWeight))
            } label: {
                Label("Add era", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Eras")
                Spacer()
                Text("\(draft.eras.count)").foregroundStyle(.secondary)
            }
        } footer: {
            Text("Weight drives the depth axis — lowest weight is deepest in the past, highest is closest to the present.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Extractors

    private var extractorsSection: some View {
        Section {
            Toggle(isOn: $draft.extractors.tags) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Surface #tags as nodes")
                        Text("Each `#tag` becomes a green tag-node every referencing note connects to.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "tag.fill").foregroundStyle(.green) }
            }
            Toggle(isOn: $draft.extractors.embeds) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Surface embeds as nodes")
                        Text("`![[file.png]]` references become file-nodes linked from the notes that embed them.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "photo.fill").foregroundStyle(.indigo) }
            }
            Toggle(isOn: $draft.extractors.placeholders) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Surface dangling wikilinks")
                        Text("`[[Name]]` references with no matching `.md` become hollow placeholder nodes.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "questionmark.circle.fill").foregroundStyle(.gray) }
            }
        } header: {
            Text("Extractors")
        }
    }

    // MARK: - Bindings + actions

    private var userTypes: [AtlasConfig.TypeSpec] {
        draft.types.filter { !syntheticNames.contains($0.name) }
    }

    /// Returns a binding to the type spec with the given id, plus a
    /// derived `.color` binding for the ColorPicker. Mutates `draft`
    /// in place by index lookup.
    private func bindingForType(_ id: String) -> TypeSpecBinding {
        TypeSpecBinding(
            base: Binding(
                get: { draft.types.first { $0.id == id } ?? .init(name: "?", color: .gray, icon: "circle") },
                set: { newValue in
                    if let idx = draft.types.firstIndex(where: { $0.id == id }) {
                        draft.types[idx] = newValue
                    }
                }
            )
        )
    }

    private func addType() {
        let new = AtlasConfig.TypeSpec(
            name: "new-type",
            color: .blue,
            icon: "circle.fill",
            folder: nil
        )
        draft.types.insert(new, at: max(0, draft.types.count - 3))  // before synthetic block
    }

    private func deleteTypes(at offsets: IndexSet) {
        // Map offsets in the filtered (user-only) list back into the
        // full types array.
        let user = userTypes
        let idsToDelete = offsets.compactMap { user.indices.contains($0) ? user[$0].id : nil }
        draft.types.removeAll { idsToDelete.contains($0.id) }
    }

    private func save() {
        guard let atlasURL = store.writableAtlasURL else {
            errorMessage = "Open or create a writable atlas first."
            return
        }
        do {
            // Document-picker URLs are security-scoped — writing without
            // bracketing fails with EPERM. Match the pattern every other
            // write path in GraphStore uses.
            try atlasURL.withSecurityScope {
                try draft.save(to: atlasURL)
            }
            store.config = draft
            isPresented = false
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// Small wrapper providing a derived `.color` binding alongside the
/// base TypeSpec binding so the ColorPicker can drive it.
private struct TypeSpecBinding {
    let base: Binding<AtlasConfig.TypeSpec>

    var wrappedValue: AtlasConfig.TypeSpec {
        get { base.wrappedValue }
        nonmutating set { base.wrappedValue = newValue }
    }

    var color: Binding<Color> {
        Binding(
            get: { base.wrappedValue.color },
            set: { base.wrappedValue.color = $0 }
        )
    }
}
