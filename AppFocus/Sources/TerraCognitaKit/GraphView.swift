import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

public struct GraphView: View {
    @StateObject private var store: GraphStore
    @State private var selectedNodeID: String?
    @State private var activeLens: Lens = .all
    @State private var showingSearch: Bool = false
    /// Drives the single folder-picker. Distinguishes Open vs Create New
    /// so we can route the result without mounting two `.fileImporter`
    /// modifiers (SwiftUI shadows all but one on the same view).
    /// `showingFolderPicker` is the SwiftUI-owned presentation flag;
    /// `folderPickerMode` is the routing tag we read in the completion
    /// handler.
    @State private var folderPickerMode: FolderPickerMode?
    @State private var showingFolderPicker: Bool = false

    enum FolderPickerMode {
        case openVault
        case createNewVault
    }

    /// Drives the GEXF file picker. After the user picks, we parse the
    /// file immediately (while the security scope is alive) and stash
    /// the document; the destination folder is picked via a separate
    /// NSOpenPanel-driven flow that doesn't fight SwiftUI's
    /// fileImporter.
    @State private var showingGEXFPicker: Bool = false
    @State private var pendingGEXFDocument: GEXFImporter.Document?
    @State private var pendingGEXFName: String?
    /// Drives the in-app Vault Settings editor (types / eras / extractors).
    @State private var showingVaultSettings: Bool = false

    /// Incremented to request a "fit to view" pass from the canvas.
    /// The canvas observes `.onChange` and animates the camera so
    /// every visible node fits — driven by the top-bar Fit button
    /// (⌘0) and by the post-load auto-frame.
    @State private var frameAllPulse: Int = 0
    /// Was the graph empty on the previous load tick? Used to detect
    /// the "first content arrived" transition and auto-frame.
    @State private var graphWasEmpty: Bool = true

    /// Currently-applied layout. Canvas writes (on restore / settle /
    /// user pick); the toolbar Layout menu reads to show a checkmark
    /// next to the active row.
    @State private var layoutAlgorithm: LayoutAlgorithm? = nil
    /// No-overlap toggle — two-way binding between the Layout menu
    /// and the canvas's post-pass.
    @State private var noOverlap: Bool = false
    /// Pulse channel for "user picked this layout from the menu".
    /// Flips non-nil → canvas applies → canvas resets to nil.
    @State private var layoutRequest: LayoutAlgorithm? = nil

    /// Drives the template picker sheet that appears before the
    /// folder picker on Create New Vault.
    @State private var showingTemplatePicker: Bool = false
    /// The template the user chose in the picker; carried across the
    /// folder-picker round-trip and consumed by `handleFolderPick`.
    @State private var pendingTemplate: Template? = nil

    /// Bridge nodes for the Systems lens — non-empty only when that
    /// lens is active. Recomputed when the graph mutates or the
    /// lens switches; cleared otherwise.
    @State private var bridgeNodeIDs: Set<String> = []
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    /// Whether the info panel (inspector / sheet) is visible. Decoupled
    /// from `selectedNodeID` so the user can hide the panel and keep a
    /// node selected, or vice versa. Auto-opens on the first selection
    /// after empty, stays whatever the user set it to thereafter.
    @State private var inspectorVisible: Bool = false

    /// Whether private nodes (those with `private: true` in front matter)
    /// are currently shown. Defaults to off — they only surface when the
    /// user explicitly toggles them in. Useful for screenshots / demos.
    @State private var showPrivate: Bool = false

    /// Browser-style back/forward stack over `selectedNodeID`.
    @StateObject private var navigation = NavigationHistory()
    /// Cached "last" state so we can compute the diff in `.onChange`.
    /// Initialized lazily on first selection change.
    @State private var lastNavState: NavigationHistory.State = .init()

    /// Radial-menu state: when set, an action wheel overlays the canvas
    /// anchored at `point`, surfacing operations for `nodeID`.
    @State private var radialTarget: RadialTarget?

    private struct RadialTarget: Equatable {
        let nodeID: String
        let point: CGPoint
    }

    /// Duplicate clusters surfaced by the vault-load review banner.
    @State private var duplicateClusters: [[String]] = []
    /// Set to true once the user has dismissed the banner this session
    /// (or opened the review modal). Prevents the banner from popping
    /// back up after they've explicitly engaged with it.
    @State private var dupeBannerDismissed: Bool = false
    @State private var showingDuplicateReview: Bool = false
    /// Structural decomposition into hubs + assigned members. Computed
    /// once when the graph loads.

    // MARK: - Ingestion state

    /// Drives the Capture sheet (text / voice dump → AI constellation).
    @State private var showingCapture: Bool = false
    /// Drives the new-node composer sheet.
    @State private var showingComposer: Bool = false
    /// Spawn point in *world* coordinates for the next-created node.
    /// `nil` → canvas picks a position (near selection or origin).
    @State private var composerSpawnWorld: CGPoint?
    /// If non-nil, the composer pre-fills body with a wikilink to this id.
    @State private var composerSeedID: String?
    /// After save, this is set so the canvas can pin/select/frame the
    /// newly-created node. The canvas clears it once it has consumed it.
    @State private var pendingNewNode: PendingNewNode?

    public init(store: GraphStore) {
        _store = StateObject(wrappedValue: store)
    }

    public init() {
        _store = StateObject(wrappedValue: GraphStore())
    }

    public var body: some View {
        ZStack(alignment: .top) {
            GraphCanvasView(
                store: store,
                selectedNodeID: $selectedNodeID,
                pendingNewNode: $pendingNewNode,
                visibleNodeFilter: visibleFilter,
                onLongPressEmptyWorld: { worldPoint in
                    // Spatial entry — node will materialize where the
                    // user pointed. Pre-link to the current selection
                    // if any (cheap "add a related thought" affordance).
                    composerSpawnWorld = worldPoint
                    composerSeedID = selectedNodeID
                    showingComposer = true
                },
                onLongPressNode: { nodeID, screenPoint in
                    radialTarget = RadialTarget(nodeID: nodeID, point: screenPoint)
                },
                frameAllPulse: $frameAllPulse,
                layoutAlgorithm: $layoutAlgorithm,
                noOverlap: $noOverlap,
                layoutRequest: $layoutRequest,
                bridgeNodeIDs: bridgeNodeIDs
            )

            // Radial action wheel anchored at the long-press point.
            if let target = radialTarget,
               let node = store.graph.nodes[target.nodeID] {
                RadialMenu(
                    center: target.point,
                    actions: radialActions(for: node),
                    onCancel: { radialTarget = nil }
                )
                .transition(.opacity)
            }

            // Top bar — back/forward + lens + find + …
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Button {
                        navigateBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!navigation.canGoBack)
                    .help("Back (⌘[)")

                    Button {
                        navigateForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!navigation.canGoForward)
                    .help("Forward (⌘])")
                }
                LensPicker(active: $activeLens, store: store)
                modePill
                Spacer()
                Menu {
                    Button {
                        presentFolderPicker(.openVault)
                    } label: {
                        Label("Open Vault Folder…", systemImage: "folder")
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    Button {
                        showingTemplatePicker = true
                    } label: {
                        Label("Create New Vault…", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showingGEXFPicker = true
                    } label: {
                        Label("Import GEXF…", systemImage: "square.and.arrow.down.on.square")
                    }
                    Divider()
                    Button {
                        showingVaultSettings = true
                    } label: {
                        Label("Vault Settings…", systemImage: "gearshape")
                    }
                    .disabled(!store.canIngest)

                    if !store.library.entries.isEmpty {
                        Divider()
                        Text("Recent")
                        ForEach(store.library.entries) { entry in
                            Button {
                                store.openLibraryEntry(entry.id)
                            } label: {
                                let suffix: String = {
                                    if let n = entry.nodeCount, let e = entry.edgeCount {
                                        return " — \(n) nodes / \(e) edges"
                                    }
                                    return ""
                                }()
                                Label(entry.displayName + suffix,
                                      systemImage: "clock.arrow.circlepath")
                            }
                        }
                        Divider()
                        Menu("Forget…") {
                            ForEach(store.library.entries) { entry in
                                Button("\(entry.displayName)", role: .destructive) {
                                    store.forgetLibraryEntry(entry.id)
                                }
                            }
                        }
                    }

                    Divider()
                    Button {
                        store.resetToDefaultVault()
                    } label: {
                        Label("Use Default (Miyazaki)", systemImage: "sparkles")
                    }
                } label: {
                    Label("Vault", systemImage: "folder")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Open a markdown vault folder (⌘O)")

                Menu {
                    Button {
                        showingCapture = true
                    } label: {
                        Label("Capture…", systemImage: "text.bubble")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!store.canIngest)

                    Button {
                        composerSpawnWorld = nil   // canvas picks (near selection)
                        composerSeedID = selectedNodeID
                        showingComposer = true
                    } label: {
                        Label("New Node…", systemImage: "circle.dashed.inset.filled")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!store.canIngest)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!store.canIngest)
                .help(store.canIngest
                      ? "Add to graph — Capture (⌘⇧N) or New Node (⌘N)"
                      : "Open or create a writable vault first.")

                Button {
                    showingSearch = true
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Find a node by name (⌘F)")

                Button {
                    frameAllPulse &+= 1
                } label: {
                    Image(systemName: "viewfinder")
                }
                .keyboardShortcut("0", modifiers: .command)
                .help("Fit graph to window (⌘0)")

                Menu {
                    ForEach(LayoutAlgorithm.allCases) { algorithm in
                        Button {
                            layoutRequest = algorithm
                        } label: {
                            // Checkmark on the active algorithm; suffix
                            // the un-shipped ones ("Soon") so the menu
                            // honestly reflects what's wired up.
                            Label {
                                HStack {
                                    Text(algorithm.displayName)
                                    if !algorithm.isImplemented {
                                        Text("(soon)").foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: layoutAlgorithm == algorithm
                                      ? "checkmark"
                                      : algorithm.systemImage)
                            }
                        }
                        .disabled(!algorithm.isImplemented)
                    }
                    Divider()
                    Toggle(isOn: $noOverlap) {
                        Label("No overlap", systemImage: "rectangle.dashed")
                    }
                } label: {
                    Image(systemName: layoutAlgorithm?.systemImage
                          ?? "point.3.connected.trianglepath.dotted")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Layout — pick how nodes are arranged")

                Button {
                    showPrivate.toggle()
                } label: {
                    Image(systemName: showPrivate ? "eye.fill" : "eye.slash")
                        .foregroundStyle(showPrivate ? .orange : .secondary)
                }
                .help(showPrivate ? "Hide private nodes" : "Show private nodes")

                Button {
                    inspectorVisible.toggle()
                } label: {
                    Image(systemName: inspectorVisible
                          ? "sidebar.right"
                          : "sidebar.squares.right")
                }
                .keyboardShortcut("i", modifiers: .command)
                .help(inspectorVisible ? "Hide info panel (⌘I)" : "Show info panel (⌘I)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial)

            // Duplicate-clusters banner (just below the top bar).
            if !duplicateClusters.isEmpty && !dupeBannerDismissed {
                VStack {
                    Spacer().frame(height: 48)
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.bubble")
                            .foregroundStyle(.orange)
                        Text("\(duplicateClusters.count) duplicate cluster\(duplicateClusters.count == 1 ? "" : "s") detected")
                            .font(.caption)
                        Spacer()
                        Button("Review") {
                            showingDuplicateReview = true
                            dupeBannerDismissed = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.orange)
                        Button {
                            dupeBannerDismissed = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                    Spacer()
                }
            }

            // Load-status pill (bottom)
            if !store.loadStatus.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text(store.loadStatus)
                            .font(.caption)
                            .padding(6)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                        Spacer()
                    }
                }
            }

            if showingSearch {
                VStack {
                    Spacer().frame(height: 56)
                    NodeSearchView(store: store) { chosen in
                        if let id = chosen { selectedNodeID = id }
                        showingSearch = false
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // Invisible Escape catcher — clears the current selection.
            // (SwiftUI lacks a direct top-level keyboard handler outside
            // a focused field, so this gives us one without stealing
            // any user-visible behaviour.)
            if selectedNodeID != nil {
                Button("") { selectedNodeID = nil }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
        .onAppear { store.loadDefaultVault() }
        .onChange(of: store.graph.nodes.count) { oldCount, newCount in
            // Recompute duplicate clusters whenever the graph changes
            // (vault load, create, delete, merge). Reset the dismissal
            // flag only on growth — shrinking after a merge shouldn't
            // re-pop the banner.
            let newClusters = store.duplicateClusters()
            if newClusters.count > duplicateClusters.count {
                dupeBannerDismissed = false
            }
            duplicateClusters = newClusters

            // Auto-frame when content first arrives. We wait a beat
            // for the layout pipeline to crossfade in the FA2 result,
            // then nudge the canvas to fit the whole cluster.
            let wasEmpty = graphWasEmpty
            graphWasEmpty = (newCount == 0)
            if wasEmpty && newCount > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    frameAllPulse &+= 1
                }
            }
        }
        // Folder-picker presentation differs by platform:
        //   - macOS uses SwiftUI's `.fileImporter` (NSOpenPanel under
        //     the hood), which handles `.folder` cleanly.
        //   - iOS / iPadOS uses a `UIDocumentPickerViewController`
        //     via `FolderPicker` — SwiftUI's `.fileImporter` for
        //     `.folder` was observed to silently no-op when presented
        //     from inside a `Menu` button on iOS.
        #if os(macOS)
        .fileImporter(
            // `folderPickerMode` is captured locally at completion
            // time before being cleared, so SwiftUI can own the
            // `isPresented` flag without us losing the routing tag.
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                handleFolderPick(urls.first)
            case .failure:
                folderPickerMode = nil
            }
        }
        #else
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker(isPresented: $showingFolderPicker) { url in
                handleFolderPick(url)
            }
            .ignoresSafeArea()
        }
        #endif
        .fileImporter(
            isPresented: $showingGEXFPicker,
            // `.gexf` files aren't registered as `.xml` on macOS, so
            // the strict XML filter would grey them out. Use the
            // permissive `.data` type and validate the extension
            // ourselves on the result side.
            allowedContentTypes: [.data, .xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { break }
                let ext = url.pathExtension.lowercased()
                guard ext == "gexf" || ext == "xml" else {
                    store.loadStatus = "Pick a .gexf file."
                    return
                }
                // Parse RIGHT NOW while the security scope is still
                // alive. Otherwise the URL's read permission may be
                // lost by the time we ask for a destination folder.
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingGEXFDocument = try GEXFImporter.parse(fileURL: url)
                    pendingGEXFName = url.deletingPathExtension().lastPathComponent
                    store.loadStatus = "Parsed \(pendingGEXFDocument?.nodes.count ?? 0) nodes — pick destination folder…"
                    promptForGEXFDestination()
                } catch {
                    store.loadStatus = "GEXF parse failed: \(error.localizedDescription)"
                }
            case .failure:
                pendingGEXFDocument = nil
                pendingGEXFName = nil
            }
        }
        .sheet(isPresented: $showingCapture) {
            CaptureSheet(
                store: store,
                isPresented: $showingCapture,
                onCommitted: { firstID in
                    if let firstID {
                        selectedNodeID = firstID
                    }
                }
            )
        }
        .sheet(isPresented: $showingVaultSettings) {
            VaultSettingsSheet(store: store, isPresented: $showingVaultSettings)
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet(
                isPresented: $showingTemplatePicker,
                onPick: { template in
                    pendingTemplate = template
                    showingTemplatePicker = false
                    // Defer the folder picker one tick so the sheet
                    // dismiss animation isn't fighting the picker
                    // present animation — same Menu/sheet race we
                    // handled in `presentFolderPicker`.
                    DispatchQueue.main.async {
                        presentFolderPicker(.createNewVault)
                    }
                }
            )
        }
        .sheet(isPresented: $showingDuplicateReview) {
            DuplicateReviewSheet(
                clusters: duplicateClusters,
                store: store,
                isPresented: $showingDuplicateReview,
                onSelect: { id in
                    selectedNodeID = id
                    showingDuplicateReview = false
                }
            )
        }
        .sheet(isPresented: $showingComposer) {
            NodeComposer(
                store: store,
                isPresented: $showingComposer,
                seedConnectionTo: composerSeedID,
                onCreated: { newID in
                    // Hand the new node off to the canvas so it can pin
                    // it at the spawn point, select it, and frame onto it.
                    pendingNewNode = PendingNewNode(
                        id: newID,
                        worldPoint: composerSpawnWorld
                    )
                    selectedNodeID = newID
                    composerSpawnWorld = nil
                    composerSeedID = nil
                },
                onOpenExisting: { existingID in
                    selectedNodeID = existingID
                    composerSpawnWorld = nil
                    composerSeedID = nil
                }
            )
        }
        // Drag a folder from Finder (macOS) or Files (iPad) onto the
        // canvas to load it as a vault. On iOS this is mostly useful
        // alongside Stage Manager and the system file browser; iPhone
        // users will keep using the picker.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            VaultDropHandler.handle(providers, store: store)
        }
        .modifier(InspectorPresentation(
            isPresented: $inspectorVisible,
            useSheet: useSheetForInspector
        ) {
            Group {
                if let id = selectedNodeID {
                    NodeInspectorView(
                        nodeID: id,
                        store: store,
                        onSelectNode: { newID in selectedNodeID = newID }
                    )
                } else {
                    ContentUnavailableView(
                        "No node selected",
                        systemImage: "circle.dashed",
                        description: Text("Tap a node in the graph to inspect it.")
                    )
                }
            }
        })
        .onChange(of: selectedNodeID) { oldValue, newValue in
            // Auto-open the panel the first time the user selects after
            // an empty-selection state. Subsequent navigations through
            // nodes keep whatever the user last set the panel to.
            if oldValue == nil && newValue != nil {
                inspectorVisible = true
            }
            recordNavIfNeeded()
        }
        .onChange(of: activeLens) { _, _ in
            refreshBridgeNodesIfNeeded()
        }
        .onChange(of: store.graph.nodes.count) { _, _ in
            refreshBridgeNodesIfNeeded()
        }
        .onChange(of: store.graph.edges.count) { _, _ in
            refreshBridgeNodesIfNeeded()
        }
    }

    /// Recompute `bridgeNodeIDs` when the Systems lens is active.
    /// Cleared (empty set) when any other lens is in use so the
    /// canvas doesn't render bridge halos.
    private func refreshBridgeNodesIfNeeded() {
        guard activeLens.isSystems else {
            if !bridgeNodeIDs.isEmpty { bridgeNodeIDs = [] }
            return
        }
        // Snapshot so the background partition pass doesn't see
        // mid-mutation state. Graph is value-typed so this is cheap.
        let graphSnapshot = store.graph
        Task.detached(priority: .userInitiated) {
            let partition = GraphAnalysis.communityPartition(of: graphSnapshot)
            let bridges = GraphAnalysis.bridgeNodes(of: graphSnapshot,
                                                     partition: partition)
            await MainActor.run { bridgeNodeIDs = bridges }
        }
    }

    /// Inspector presentation rule:
    ///   - macOS: side panel (pointer-driven, plenty of room)
    ///   - iPad regular width (landscape / full-screen): side panel
    ///     — the iPad has the real-estate, and the sheet was obscuring
    ///     too much of the canvas
    ///   - iPad compact (split view / Slide Over) + iPhone: sheet
    ///     with detents
    /// Compact pill in the toolbar showing the vault's current mode.
    /// Pure display today — mode is set at vault creation via the
    /// template picker; switching modes mid-vault is out of scope for
    /// Phase 2.
    @ViewBuilder
    private var modePill: some View {
        let mode = store.config.mode
        HStack(spacing: 4) {
            Image(systemName: mode.systemImage)
                .imageScale(.small)
            Text(mode.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.secondary.opacity(0.15))
        )
        .foregroundStyle(.secondary)
        .help("This vault is in \(mode.displayName) mode.")
    }

    private var useSheetForInspector: Bool {
        #if os(iOS)
        return hSizeClass == .compact
        #else
        return false
        #endif
    }

    /// Push the current selection onto the back stack before applying
    /// a new state — unless `navigation` is the one driving the
    /// change (goBack / goForward).
    private func recordNavIfNeeded() {
        let now = NavigationHistory.State(selectedNodeID: selectedNodeID)
        defer { lastNavState = now }
        if navigation.suppressRecording { return }
        navigation.record(now, previous: lastNavState)
    }

    private func navigateBack() {
        let now = NavigationHistory.State(selectedNodeID: selectedNodeID)
        guard let previous = navigation.goBack(from: now) else { return }
        applyNavState(previous)
    }

    private func navigateForward() {
        let now = NavigationHistory.State(selectedNodeID: selectedNodeID)
        guard let next = navigation.goForward(from: now) else { return }
        applyNavState(next)
    }

    private func applyNavState(_ state: NavigationHistory.State) {
        navigation.suppressRecording = true
        selectedNodeID = state.selectedNodeID
        lastNavState = state
        // Yield so the .onChange handlers flush before we re-enable.
        Task { @MainActor in
            await Task.yield()
            navigation.suppressRecording = false
        }
    }

    /// Set the routing mode and present the folder picker. The
    /// presentation is deferred by one runloop tick so the host
    /// `Menu` has time to dismiss before the picker mounts — on iOS,
    /// firing them in the same tick causes the picker to silently
    /// drop, which is why "Open Vault Folder…" appeared to do nothing.
    private func presentFolderPicker(_ mode: FolderPickerMode) {
        folderPickerMode = mode
        DispatchQueue.main.async {
            showingFolderPicker = true
        }
    }

    /// Route a picked folder URL based on the currently-active
    /// `folderPickerMode`. Shared between the macOS `.fileImporter`
    /// path and the iOS `FolderPicker` (UIDocumentPicker) path.
    private func handleFolderPick(_ url: URL?) {
        let mode = folderPickerMode
        folderPickerMode = nil
        guard let url else { return }
        switch mode {
        case .openVault:
            store.load(from: url)
        case .createNewVault:
            // The user picked a parent folder; materialize a child
            // named after the chosen template inside it (or use the
            // chosen folder directly if it's already empty). Template
            // was selected earlier in `TemplatePickerSheet` and
            // stashed on `pendingTemplate`.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let template = pendingTemplate
            pendingTemplate = nil
            let folderName = template.map { "\($0.name) Vault" }
                ?? "Terra Cognita Vault"
            let target: URL = {
                let fm = FileManager.default
                if let items = try? fm.contentsOfDirectory(at: url,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles]),
                   items.isEmpty {
                    return url
                }
                return url.appendingPathComponent(folderName)
            }()
            store.createNewVault(at: target, template: template)
        case .none:
            break
        }
    }

    /// Step 2 of GEXF import: ask the user where to materialize the
    /// new vault. Uses NSOpenPanel directly on macOS — SwiftUI's
    /// `.fileImporter` runs into mount conflicts when fired
    /// back-to-back with another importer. On iOS this is a no-op for
    /// now; iPad GEXF import can layer on UIDocumentPicker later.
    private func promptForGEXFDestination() {
        guard let doc = pendingGEXFDocument,
              let basename = pendingGEXFName else { return }
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for the imported vault"
        panel.message = "A new folder named \"\(basename)\" will be created here, with one .md per GEXF node."
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            DispatchQueue.main.async {
                defer {
                    pendingGEXFDocument = nil
                    pendingGEXFName = nil
                }
                guard response == .OK, let parent = panel.url else { return }
                let target = parent.appendingPathComponent(basename)
                store.importGEXFDocument(doc, into: target)
            }
        }
        #else
        // iOS: can't sequence two pickers cleanly yet. Surface the
        // expected destination so the user can manually move it later.
        let documentsURL = FileManager.default.urls(for: .documentDirectory,
                                                    in: .userDomainMask).first
        guard let parent = documentsURL else {
            store.loadStatus = "Couldn't find Documents folder for GEXF import."
            pendingGEXFDocument = nil
            pendingGEXFName = nil
            return
        }
        let target = parent.appendingPathComponent(basename)
        store.importGEXFDocument(doc, into: target)
        pendingGEXFDocument = nil
        pendingGEXFName = nil
        #endif
    }

    /// Compose the radial menu's actions for a given node. Each action
    /// dismisses the wheel after committing.
    private func radialActions(for node: Node) -> [RadialMenu.Action] {
        var actions: [RadialMenu.Action] = []

        actions.append(RadialMenu.Action(
            id: "open",
            label: "Open",
            systemImage: "doc.text",
            tint: .blue
        ) {
            selectedNodeID = node.id
            inspectorVisible = true
            radialTarget = nil
        })

        actions.append(RadialMenu.Action(
            id: "find-links",
            label: "AI links",
            systemImage: "link",
            tint: .indigo
        ) {
            selectedNodeID = node.id
            inspectorVisible = true
            radialTarget = nil
        })

        actions.append(RadialMenu.Action(
            id: "center",
            label: "Center",
            systemImage: "scope",
            tint: .teal
        ) {
            selectedNodeID = node.id
            radialTarget = nil
        })

        if store.canIngest {
            actions.append(RadialMenu.Action(
                id: "delete",
                label: "Delete",
                systemImage: "trash",
                tint: .red
            ) {
                _ = store.deleteNode(node.id)
                if selectedNodeID == node.id { selectedNodeID = nil }
                radialTarget = nil
            })
        }

        actions.append(RadialMenu.Action(
            id: "cancel",
            label: "Cancel",
            systemImage: "xmark",
            tint: .gray
        ) {
            radialTarget = nil
        })

        return actions
    }

    /// Composed visible-node filter:
    ///   - Lens type filter, if any
    ///   - Private nodes (front-matter `private: true`) hidden unless
    ///     the eye-toggle is on.
    private var visibleFilter: ((Node) -> Bool)? {
        let typeFilter = activeLens.makeTypeFilter()
        let showPrivateNow = showPrivate
        // Always return a closure so the canvas can also use it for
        // privacy filtering even when the "All" lens is active.
        return { node in
            if !showPrivateNow && Self.isPrivate(node) { return false }
            return typeFilter?(node) ?? true
        }
    }

    /// A node is "private" when its front-matter has `private: true`
    /// (case-insensitive). Edges to/from private nodes are dropped when
    /// `showPrivate` is off.
    static func isPrivate(_ node: Node) -> Bool {
        let v = (node.attributes["private"] ?? "").lowercased()
        return v == "true" || v == "yes" || v == "1"
    }
}

// MARK: - Inspector adaptive presentation

/// Picks between `.inspector(isPresented:)` (side panel, macOS + iPad
/// regular width) and `.sheet(isPresented:)` (iPhone / iPad compact)
/// based on `useSheet`. Keeps a single call-site in GraphView.
private struct InspectorPresentation<InspectorContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let useSheet: Bool
    @ViewBuilder var content: () -> InspectorContent

    func body(content base: Content) -> some View {
        if useSheet {
            base.sheet(isPresented: $isPresented) {
                content()
                #if os(iOS)
                    // Three detents — a small "peek" so the canvas stays
                    // visible behind it, plus the standard medium/large.
                    .presentationDetents([.fraction(0.28), .medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationContentInteraction(.scrolls)
                #endif
            }
        } else {
            base.inspector(isPresented: $isPresented) {
                content()
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 520)
            }
        }
    }
}

// MARK: - Subnet badge

/// Modal that reviews duplicate-slug clusters found at vault load and
/// offers one-click merge (with side-by-side preview). The "winner" of
/// each merge is the node the user taps as the keeper.
private struct DuplicateReviewSheet: View {
    let clusters: [[String]]
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool
    var onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Each row is a cluster of nodes whose normalized labels match. Pick which one to keep — the others will be merged in (their wikilinks redirected, bodies appended, files snapshotted as `.bak`).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(cluster, id: \.self) { id in
                                if let node = store.graph.nodes[id] {
                                    HStack(spacing: 8) {
                                        Button {
                                            onSelect(id)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(node.label).font(.callout)
                                                Text(id).font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        Spacer()
                                        Menu {
                                            ForEach(cluster.filter { $0 != id }, id: \.self) { loserID in
                                                if let loser = store.graph.nodes[loserID] {
                                                    Button("Merge \"\(loser.label)\" in") {
                                                        _ = store.mergeNode(loserID, into: id)
                                                    }
                                                }
                                            }
                                        } label: {
                                            Label("Keep this", systemImage: "arrow.triangle.merge")
                                                .font(.caption)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(.green.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.green)
                                        }
                                        .menuStyle(.borderlessButton)
                                        .fixedSize()
                                    }
                                    .padding(8)
                                    .background(.secondary.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Duplicate clusters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 460, idealHeight: 600)
    }
}

/// Marker for a freshly-created node so the canvas can pin/select/frame
/// it on the next layout pass. Cleared by the canvas once consumed.
struct PendingNewNode: Equatable {
    let id: String
    /// World-coord spawn point. `nil` → canvas picks (near selection / origin).
    let worldPoint: CGPoint?
}

// MARK: - Lenses

/// A semantic view over the graph. `all` is always present; the
/// per-type lenses are generated dynamically from the vault's
/// `VaultConfig.types` so a custom ontology surfaces correctly in the
/// picker.
struct Lens: Hashable, Identifiable {
    enum Kind: Hashable {
        case all
        case type(String)   // type name from VaultConfig.types
        /// Systems lens: doesn't filter nodes, but signals to the
        /// canvas that bridge nodes (members of one community with
        /// edges into another) should be visually emphasized.
        case systems
    }

    var kind: Kind
    var label: String
    var icon: String

    var id: Kind { kind }

    static let all = Lens(kind: .all,
                          label: "All",
                          icon: "circle.grid.3x3.fill")
    static let systems = Lens(kind: .systems,
                              label: "Systems",
                              icon: "network")

    /// All lenses available for the active vault: `all`, then one per
    /// declared type, then `Systems` as the topology view. Order
    /// matters for the picker.
    static func all(for config: VaultConfig) -> [Lens] {
        var list: [Lens] = [.all]
        for t in config.types {
            list.append(Lens(
                kind: .type(t.name),
                label: t.displayName ?? (t.name.capitalized + "s"),
                icon: t.icon
            ))
        }
        list.append(.systems)
        return list
    }

    /// Pure type-based filter. `nil` means "include everything".
    /// Systems doesn't filter — it returns nil and lets the canvas
    /// drive emphasis instead.
    func makeTypeFilter() -> ((Node) -> Bool)? {
        switch kind {
        case .all, .systems: return nil
        case .type(let typeName):
            return { ($0.type ?? "").lowercased() == typeName.lowercased() }
        }
    }

    var isSystems: Bool {
        if case .systems = kind { return true }
        return false
    }
}

private struct LensPicker: View {
    @Binding var active: Lens
    @ObservedObject var store: GraphStore

    var body: some View {
        Menu {
            ForEach(Lens.all(for: store.config)) { lens in
                Button {
                    active = lens
                } label: {
                    Label(lens.label + countSuffix(lens), systemImage: lens.icon)
                }
            }
        } label: {
            Label(active.label, systemImage: active.icon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func countSuffix(_ lens: Lens) -> String {
        guard let filter = lens.makeTypeFilter() else { return "" }
        let n = store.graph.nodes.values.filter(filter).count
        return n > 0 ? " (\(n))" : ""
    }
}
