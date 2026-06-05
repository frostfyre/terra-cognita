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
            // Iterate indices INTO `draft.types` (not over a filtered copy)
            // so each row gets a direct binding via `$draft.types[idx]`.
            // The previous bindingForType wrapper looked up by stale id on
            // each set, which let SwiftUI tear down the TextField mid-edit
            // and drop the iOS keyboard after every character.
            ForEach(userTypeIndices, id: \.self) { idx in
                typeRow(at: idx)
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
    private func typeRow(at idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: draft.types[idx].icon)
                    .foregroundStyle(draft.types[idx].color)
                    .frame(width: 22)
                // iOS default autocapitalization fights with `.lowercased()`
                // in the setter: user types "h" → iOS caps it to "H" → setter
                // reverts to "h" → SwiftUI treats it as an external mutation
                // and drops focus → keyboard dismisses on every character.
                // Disable autocap/autocorrect for these technical strings.
                TextField("name", text: Binding(
                    get: { draft.types[idx].name },
                    set: { draft.types[idx].name = $0.lowercased() }
                ))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                ColorPicker("", selection: $draft.types[idx].color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36)
            }
            HStack(spacing: 6) {
                TextField("display name (optional)",
                          text: Binding(
                            get: { draft.types[idx].displayName ?? "" },
                            set: { draft.types[idx].displayName = $0.isEmpty ? nil : $0 }
                          ))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                TextField("SF Symbol", text: $draft.types[idx].icon)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            TextField("folder (optional)",
                      text: Binding(
                        get: { draft.types[idx].folder ?? "" },
                        set: { draft.types[idx].folder = $0.isEmpty ? nil : $0 }
                      ))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
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
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
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

    /// Indices into `draft.types` of all non-synthetic types — used by
    /// the section so each row binds directly via `$draft.types[idx]`.
    private var userTypeIndices: [Int] {
        draft.types.indices.filter { !syntheticNames.contains(draft.types[$0].name) }
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
        // Offsets index into userTypeIndices (the ForEach data source);
        // map each one back to its position in `draft.types`, then remove.
        let userIdx = userTypeIndices
        let draftIdxToDelete = offsets.compactMap { userIdx.indices.contains($0) ? userIdx[$0] : nil }
        draft.types.remove(atOffsets: IndexSet(draftIdxToDelete))
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
