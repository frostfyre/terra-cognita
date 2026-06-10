import SwiftUI

/// In-app music picker for binding an Apple Music item (song, album,
/// or playlist) to the current atlas. Search-first: the user types a
/// query, results stream in with artwork, tap to select, save. Keeps
/// the URL-paste path as a power-user fallback via a "Have a link?"
/// disclosure — useful when the user has a specific share-URL they
/// want to lock in or when catalog search isn't returning the right
/// item.
struct MusicBindingPickerSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var results: MusicService.SearchResult = .empty
    @State private var searching: Bool = false
    @State private var selectedItem: MusicService.SearchItem?
    @State private var errorMessage: String?

    @State private var showingURLEntry: Bool = false

    var body: some View {
        NavigationStack {
            content
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
                            .disabled(selectedItem == nil)
                    }
                }
                .sheet(isPresented: $showingURLEntry) {
                    URLEntrySheet(
                        existing: store.config.audio.suggestedMusic,
                        isPresented: $showingURLEntry,
                        onSave: { music in
                            store.setSuggestedMusic(music)
                            isPresented = false
                        }
                    )
                }
        }
        .onAppear(perform: preloadExisting)
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560, idealHeight: 640)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if let message = errorMessage {
                statusLine(message: message)
            }
            resultsList
            urlFallback
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Apple Music", text: $query)
                .textFieldStyle(.plain)
                .disableAutocorrection(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: query) { _, newValue in
                    scheduleSearch(for: newValue)
                }
            if searching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func statusLine(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var resultsList: some View {
        switch results {
        case .empty:
            emptyState
        case .results(let songs, let albums, let playlists):
            List {
                section(title: "Playlists", items: playlists,
                        icon: "music.note.list")
                section(title: "Albums", items: albums,
                        icon: "square.stack.fill")
                section(title: "Songs", items: songs,
                        icon: "music.note")
            }
            .listStyle(.inset)
        case .denied, .unavailable, .failure:
            // Status line above carries the user-facing message;
            // give the list area an empty look so the URL fallback
            // is the obvious next step.
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty
                 ? "Search to bind a soundtrack."
                 : "No results.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func section(title: String,
                         items: [MusicService.SearchItem],
                         icon: String) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    row(for: item)
                }
            } header: {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(for item: MusicService.SearchItem) -> some View {
        let isSelected = selectedItem?.id == item.id
        return Button {
            selectedItem = item
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: item.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.tertiary)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var urlFallback: some View {
        VStack(spacing: 6) {
            Divider()
            Button {
                showingURLEntry = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .imageScale(.small)
                    Text("Have a share link? Paste it instead")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func preloadExisting() {
        guard let existing = store.config.audio.suggestedMusic else { return }
        selectedItem = MusicService.SearchItem(
            id: existing.id,
            kind: existing.kind,
            title: existing.displayName,
            subtitle: existing.attribution,
            artworkURL: nil
        )
        query = existing.displayName
        scheduleSearch(for: query)
    }

    private func scheduleSearch(for newQuery: String) {
        debounceTask?.cancel()
        errorMessage = nil
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = .empty
            searching = false
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            let result = await MusicService.shared.search(query: trimmed)
            guard !Task.isCancelled else { return }
            results = result
            searching = false
            switch result {
            case .denied:
                errorMessage = "Apple Music access denied — paste a share link instead."
            case .unavailable:
                errorMessage = "Apple Music isn't available right now."
            case .failure:
                errorMessage = "Search failed — try again, or paste a share link."
            case .empty, .results:
                errorMessage = nil
            }
        }
    }

    private func save() {
        guard let item = selectedItem else { return }
        let music = AtlasConfig.SuggestedMusic(
            kind: item.kind,
            id: item.id,
            displayName: item.title,
            attribution: item.subtitle
        )
        store.setSuggestedMusic(music)
        isPresented = false
    }
}

// MARK: - URL fallback sheet

/// Power-user fallback when catalog search isn't enough — paste an
/// Apple Music share URL directly, parse it, save. The original
/// picker behavior, preserved so people who already know what
/// they want can bypass the search step.
private struct URLEntrySheet: View {
    let existing: AtlasConfig.SuggestedMusic?
    @Binding var isPresented: Bool
    let onSave: (AtlasConfig.SuggestedMusic) -> Void

    @State private var urlInput: String = ""
    @State private var displayName: String = ""
    @State private var attribution: String = ""
    @State private var parsedKind: AtlasConfig.SuggestedMusic.Kind?
    @State private var parsedID: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste Apple Music URL", text: $urlInput, axis: .vertical)
                        .lineLimit(2...3)
                        .textFieldStyle(.plain)
                        .disableAutocorrection(true)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onChange(of: urlInput) { _, _ in parse() }
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
                            Text("Use Share → Copy Link from the Music app.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Share Link")
                }

                Section {
                    TextField("Name", text: $displayName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    TextField("Attribution (optional)", text: $attribution)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                } header: {
                    Text("Details")
                }

                if let message = errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Paste Link")
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
        .onAppear(perform: preload)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 380, idealHeight: 420)
        #endif
    }

    private var canSave: Bool {
        parsedKind != nil
            && !(parsedID ?? "").isEmpty
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func preload() {
        guard let existing else { return }
        displayName = existing.displayName
        attribution = existing.attribution ?? ""
        parsedKind = existing.kind
        parsedID = existing.id
        urlInput = "https://music.apple.com/us/\(existing.kind.rawValue)/_/\(existing.id)"
    }

    private func parse() {
        errorMessage = nil
        guard let parsed = MusicURLParser.parse(urlInput) else {
            parsedKind = nil
            parsedID = nil
            return
        }
        parsedKind = parsed.kind
        parsedID = parsed.id
        Task { @MainActor in
            let result = await MusicService.shared.lookup(
                kind: parsed.kind, id: parsed.id)
            if case .found(let name, let attr) = result {
                if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                    displayName = name
                }
                if let a = attr,
                   attribution.trimmingCharacters(in: .whitespaces).isEmpty {
                    attribution = a
                }
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
        onSave(music)
        isPresented = false
    }
}
