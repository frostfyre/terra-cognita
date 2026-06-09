import SwiftUI

/// Manual music-picker presented from Atlas Settings. The user pastes
/// an Apple Music share URL; the app parses the kind + ID, fetches
/// the displayName + attribution from the catalog (if MusicKit
/// authorization permits), and saves it as the atlas's
/// `audio.suggestedMusic` binding.
///
/// Graceful fallback when catalog lookup is unavailable (denied,
/// macOS-MusicKit-entitlement-missing, etc.): the user can type
/// displayName + attribution by hand and save — playback may still
/// work if the ID is valid, and even if it doesn't, the binding is
/// visible in the popover so the user can re-edit later.
struct MusicBindingPickerSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    @State private var urlInput: String = ""
    @State private var displayName: String = ""
    @State private var attribution: String = ""
    @State private var parsedKind: AtlasConfig.SuggestedMusic.Kind?
    @State private var parsedID: String?
    @State private var lookupState: LookupState = .idle
    @State private var errorMessage: String?

    private enum LookupState {
        case idle, looking, done, failed
    }

    var body: some View {
        NavigationStack {
            Form {
                urlSection
                detailsSection
                if let message = errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Atlas Soundtrack")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: preloadExisting)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 460, idealHeight: 520)
        #endif
    }

    // MARK: - Sections

    private var urlSection: some View {
        Section {
            TextField("Paste Apple Music URL", text: $urlInput,
                      axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.plain)
                .disableAutocorrection(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: urlInput) { _, _ in
                    parseAndLookup()
                }

            if let kind = parsedKind, let id = parsedID {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                    Text("Recognized as \(kind.rawValue) · \(id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !urlInput.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                    Text("Not an Apple Music URL we recognize. Use Share → Copy Link from the Music app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Source")
        } footer: {
            Text("In the Music app, find the playlist, album, or song you want. Tap Share → Copy Link, then paste here.")
                .font(.caption2)
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Name", text: $displayName)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
            TextField("Attribution (optional)", text: $attribution)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
            if lookupState == .looking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking up…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Details")
        } footer: {
            Text("Auto-filled from Apple Music when the URL resolves. Editable so you can fine-tune what shows in the suggestion popover.")
                .font(.caption2)
        }
    }

    // MARK: - Computed

    private var canSave: Bool {
        parsedKind != nil
            && !(parsedID ?? "").isEmpty
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func preloadExisting() {
        guard let existing = store.config.audio.suggestedMusic else { return }
        displayName = existing.displayName
        attribution = existing.attribution ?? ""
        parsedKind = existing.kind
        parsedID = existing.id
        // Reconstruct a reasonable URL so the user can see what they
        // had picked before; the parser will treat any subsequent
        // edit as a new paste.
        urlInput = "https://music.apple.com/us/\(existing.kind.rawValue)/_/\(existing.id)"
    }

    private func parseAndLookup() {
        errorMessage = nil
        guard let parsed = MusicURLParser.parse(urlInput) else {
            parsedKind = nil
            parsedID = nil
            return
        }
        parsedKind = parsed.kind
        parsedID = parsed.id

        // Catalog lookup is fire-and-forget — auto-fill on success,
        // ignore failure (user can type name by hand).
        lookupState = .looking
        Task { @MainActor in
            let result = await MusicService.shared.lookup(
                kind: parsed.kind, id: parsed.id)
            switch result {
            case .found(let name, let attr):
                if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                    displayName = name
                }
                if let a = attr,
                   attribution.trimmingCharacters(in: .whitespaces).isEmpty {
                    attribution = a
                }
                lookupState = .done
            case .notFound:
                lookupState = .failed
                errorMessage = "Couldn't find that on Apple Music. Type a name below and save anyway, or re-check the URL."
            case .denied:
                lookupState = .failed
                errorMessage = "Apple Music access denied — type a name below to continue without auto-fill."
            case .unavailable:
                lookupState = .failed
                errorMessage = "Apple Music isn't available right now — type a name below to continue."
            case .failure:
                lookupState = .failed
                errorMessage = "Lookup failed — type a name below to continue."
            }
        }
    }

    private func save() {
        guard let kind = parsedKind, let id = parsedID else { return }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAttribution = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        let music = AtlasConfig.SuggestedMusic(
            kind: kind,
            id: id,
            displayName: trimmedName,
            attribution: trimmedAttribution.isEmpty ? nil : trimmedAttribution
        )
        store.setSuggestedMusic(music)
        isPresented = false
    }
}
