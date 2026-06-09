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
    @State private var showingMusicPicker: Bool = false
    /// Snapshot of non-synthetic type names at the moment the sheet
    /// opened, in their position order. On save we diff this against
    /// the current names to detect renames, then sweep the graph and
    /// rewrite every affected node's `type:` front-matter. Without
    /// this, renaming "person" → "people" would orphan every Person
    /// node under a name the config no longer recognizes.
    @State private var originalUserTypeNames: [String]

    init(store: GraphStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
        // Start from the live config; user edits build up locally
        // until they hit Save.
        self._draft = State(initialValue: store.config)
        let synthetic: Set<String> = ["tag", "embed", "placeholder"]
        self._originalUserTypeNames = State(
            initialValue: store.config.types
                .filter { !synthetic.contains($0.name) }
                .map(\.name)
        )
    }

    private let syntheticNames: Set<String> = ["tag", "embed", "placeholder"]

    var body: some View {
        NavigationStack {
            Form {
                typesSections
                erasSection
                extractorsSection
                audioSection
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

    /// One Section per type so the Form gives each its own visual card with
    /// a header identifying which type's fields you're editing. Previous
    /// layout crammed every type into three back-to-back rows inside a
    /// single section, with no visual separation between types.
    @ViewBuilder
    private var typesSections: some View {
        ForEach(userTypeIndices, id: \.self) { idx in
            typeSection(at: idx)
        }
        Section {
            Button {
                addType()
            } label: {
                Label("Add type", systemImage: "plus.circle")
            }
        } footer: {
            Text("Built-in synthetic types (tag / embed / placeholder) are always available and aren't shown here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func typeSection(at idx: Int) -> some View {
        Section {
            // iOS default autocapitalization fights with `.lowercased()`
            // in the setter: typed "h" → iOS caps it to "H" → setter
            // reverts to "h" → SwiftUI treats that as an external
            // mutation and drops focus → keyboard dismisses on every
            // character. Disable autocap/autocorrect on these technical
            // strings so the setter has nothing to revert.
            LabeledContent("Name") {
                TextField("name", text: Binding(
                    get: { draft.types[idx].name },
                    set: { draft.types[idx].name = $0.lowercased() }
                ))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            }
            LabeledContent("Display name") {
                TextField("optional", text: Binding(
                    get: { draft.types[idx].displayName ?? "" },
                    set: { draft.types[idx].displayName = $0.isEmpty ? nil : $0 }
                ))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
            }
            LabeledContent("SF Symbol") {
                TextField("circle.fill", text: $draft.types[idx].icon)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            ColorPicker("Color", selection: $draft.types[idx].color, supportsOpacity: false)
            LabeledContent("Folder") {
                TextField("optional", text: Binding(
                    get: { draft.types[idx].folder ?? "" },
                    set: { draft.types[idx].folder = $0.isEmpty ? nil : $0 }
                ))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            }
            Button(role: .destructive) {
                draft.types.remove(at: idx)
            } label: {
                Label("Delete type", systemImage: "trash")
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: draft.types[idx].icon)
                    .foregroundStyle(draft.types[idx].color)
                Text(draft.types[idx].name.isEmpty ? "(unnamed)" : draft.types[idx].name)
                    .textCase(nil)
            }
        }
    }

    // MARK: - Eras

    private var erasSection: some View {
        Section {
            // Index-based identity for the same reason as types — `EraSpec.id`
            // is the editable name, so binding-driven ForEach would re-create
            // the row on every keystroke.
            ForEach(Array(draft.eras.indices), id: \.self) { idx in
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("name", text: $draft.eras[idx].name)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        TextField("0", value: $draft.eras[idx].weight, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                    }
                } label: {
                    Text("Era \(idx + 1)")
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

    // MARK: - Audio

    private var audioSection: some View {
        Section {
            Toggle(isOn: $draft.audio.chimeEnabled) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Chime on selection")
                        Text("Selecting a node rings a short chord — one tone per neighbor, pitch from node type, panned across the stereo field. AirPods spatial audio works.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "waveform").foregroundStyle(.yellow) }
            }

            // Soundtrack row — current binding (or "None"), plus a
            // Change button that opens the manual picker. Clear
            // wipes the binding so the suggestion never offers.
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "music.note")
                    .foregroundStyle(.yellow)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Soundtrack")
                    if let m = draft.audio.suggestedMusic {
                        Text(m.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let a = m.attribution, !a.isEmpty {
                            Text(a)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("None — atlas plays no music")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(spacing: 4) {
                    Button(draft.audio.suggestedMusic == nil ? "Set…" : "Change…") {
                        showingMusicPicker = true
                    }
                    .buttonStyle(.bordered)
                    if draft.audio.suggestedMusic != nil {
                        Button("Clear", role: .destructive) {
                            draft.audio.suggestedMusic = nil
                            // Persist immediately via the same path
                            // the picker uses — keeps in-memory and
                            // on-disk in sync so the popover badge
                            // disappears right away.
                            store.setSuggestedMusic(nil)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Audio")
        } footer: {
            Text("Audio settings are per-atlas — turning chime on here doesn't affect other atlases. Mixes with whatever music you're already playing.")
                .font(.caption2)
        }
        .sheet(isPresented: $showingMusicPicker) {
            MusicBindingPickerSheet(store: store, isPresented: $showingMusicPicker)
                .onDisappear {
                    // Picker writes through `store.setSuggestedMusic`,
                    // which updates `store.config.audio.suggestedMusic`.
                    // Re-seed `draft` so the row redraws with the new
                    // binding.
                    draft.audio.suggestedMusic = store.config.audio.suggestedMusic
                }
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
            applyTypeRenames()
            isPresented = false
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// Sweep any node whose `type:` matches a renamed type, rewriting
    /// the front-matter to the new name. Only fires when no types
    /// were added or deleted in the same edit — otherwise position-
    /// based pairing would mispair, and we prefer skipping silently
    /// over rewriting nodes under the wrong type.
    private func applyTypeRenames() {
        let currentUserTypeNames = userTypes.map(\.name)
        guard currentUserTypeNames.count == originalUserTypeNames.count else { return }
        let renames: [(old: String, new: String)] = zip(originalUserTypeNames, currentUserTypeNames)
            .compactMap { old, new in
                let oldNorm = old.lowercased()
                let newNorm = new.lowercased()
                return oldNorm != newNorm ? (old: oldNorm, new: newNorm) : nil
            }
        guard !renames.isEmpty else { return }
        for (old, new) in renames {
            let affectedIDs = store.graph.nodes.values
                .filter { $0.type?.lowercased() == old }
                .map(\.id)
            for nodeID in affectedIDs {
                if let err = store.setType(in: nodeID, to: new) {
                    print("Type rename failed for node \(nodeID): \(err)")
                }
            }
        }
    }
}
