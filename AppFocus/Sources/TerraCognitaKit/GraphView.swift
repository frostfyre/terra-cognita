import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

public struct GraphView: View {
    @StateObject var store: GraphStore
    @State var selectedNodeID: String?
    @State var activeLens: Lens = .all
    @State var showingSearch: Bool = false
    /// One modal sheet at a time. Folds six previously-separate
    /// `showing*` booleans (Capture, Composer, AtlasSettings,
    /// ImportRecipe, TemplatePicker, DuplicateReview) into one
    /// optional — enforces mutual exclusion structurally and
    /// collapses the GraphView state count. Sub-sheets keep their
    /// existing `isPresented: Binding<Bool>` API; we synthesize
    /// the binding per kind via `sheetBinding(for:)`.
    @State var activeSheet: ActiveSheet?

    enum ActiveSheet: Identifiable, Hashable {
        case addNode
        case atlasSettings
        case importRecipe
        case templatePicker
        case duplicateReview

        var id: Self { self }
    }
    /// Drives the single folder-picker. Distinguishes Open vs Create New
    /// so we can route the result without mounting two `.fileImporter`
    /// modifiers (SwiftUI shadows all but one on the same view).
    /// `showingFolderPicker` is the SwiftUI-owned presentation flag;
    /// `folderPickerMode` is the routing tag we read in the completion
    /// handler.
    @State var folderPickerMode: FolderPickerMode?
    @State var showingFolderPicker: Bool = false

    enum FolderPickerMode {
        case openAtlas
        case createNewAtlas
    }

    /// Drives the GEXF file picker. After the user picks, we parse the
    /// file immediately (while the security scope is alive) and stash
    /// the document; the destination folder is picked via a separate
    /// NSOpenPanel-driven flow that doesn't fight SwiftUI's
    /// fileImporter.
    @State var showingGEXFPicker: Bool = false
    @State var pendingGEXFDocument: GEXFImporter.Document?
    @State var pendingGEXFName: String?

    /// Incremented to request a "fit to view" pass from the canvas.
    /// The canvas observes `.onChange` and animates the camera so
    /// every visible node fits — driven by the top-bar Fit button
    /// (⌘0) and by the post-load auto-frame.
    @State var frameAllPulse: Int = 0
    /// Set after a successful atlas load completes; cleared after the
    /// next `layoutSettleTick` advance triggers the auto-frame + fade.
    /// Without this gate the fade would fire on every settle event,
    /// not just the one that follows a fresh load.
    @State var awaitingLayoutSettle: Bool = false

    /// Currently-applied layout. Canvas writes (on restore / settle /
    /// user pick); the toolbar Layout menu reads to show a checkmark
    /// next to the active row.
    @State var layoutAlgorithm: LayoutAlgorithm? = nil
    /// No-overlap toggle — two-way binding between the Layout menu
    /// and the canvas's post-pass.
    @State var noOverlap: Bool = false
    /// Pulse channel for "user picked this layout from the menu".
    /// Flips non-nil → canvas applies → canvas resets to nil.
    @State var layoutRequest: LayoutAlgorithm? = nil

    /// Selection-highlight radius in BFS hops (1...4). Persisted
    /// per-atlas via `LayoutPersistence`. Driven from the radial
    /// Hops dial; the canvas restores it on load and reads on each
    /// frame.
    @State var highlightDepth: Int = 1

    /// The template the user chose in the picker; carried across the
    /// folder-picker round-trip and consumed by `handleFolderPick`.
    @State var pendingTemplate: Template? = nil

    /// Bridge nodes for the Systems lens — non-empty only when that
    /// lens is active. Recomputed when the graph mutates or the
    /// lens switches; cleared otherwise.
    @State var bridgeNodeIDs: Set<String> = []
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var hSizeClass
    #endif

    /// Whether the info panel (inspector / sheet) is visible. Decoupled
    /// from `selectedNodeID` so the user can hide the panel and keep a
    /// node selected, or vice versa. Auto-opens on the first selection
    /// after empty, stays whatever the user set it to thereafter.
    @State var inspectorVisible: Bool = false

    /// Whether private nodes (those with `private: true` in front matter)
    /// are currently shown. Defaults to off — they only surface when the
    /// user explicitly toggles them in. Useful for screenshots / demos.
    @State var showPrivate: Bool = false

    /// Browser-style back/forward stack over `selectedNodeID`.
    @StateObject var navigation = NavigationHistory()
    /// Cached "last" state so we can compute the diff in `.onChange`.
    /// Initialized lazily on first selection change.
    @State var lastNavState: NavigationHistory.State = .init()

    /// Radial-menu state: when set, an action wheel overlays the canvas
    /// anchored at `point`, surfacing operations for `nodeID`.
    @State var radialTarget: RadialTarget?

    struct RadialTarget: Equatable {
        let nodeID: String
        let point: CGPoint
    }

    /// Side-channel from the per-node radial → the inspector. Set
    /// when the user picks an AI op or edit affordance from the
    /// wheel; the inspector reads on appear (or change of selection)
    /// and clears it back to `nil` once it's consumed. Keeps the
    /// inspector authoritative over which view actually runs the op
    /// while letting the radial be the entry point.
    @State var pendingInspectorIntent: InspectorIntent? = nil

    /// Global (canvas-level) radial state — set when the user
    /// long-presses empty canvas. The world point lets "New Node
    /// here" spawn at the press point; the screen point anchors
    /// the wheel.
    @State var globalRadial: GlobalRadialTarget?

    struct GlobalRadialTarget: Equatable {
        let world: CGPoint
        let screen: CGPoint
    }

    /// Duplicate clusters surfaced by the atlas-load review banner.
    @State var duplicateClusters: [[String]] = []
    /// Set to true once the user has dismissed the banner this session
    /// (or opened the review modal). Prevents the banner from popping
    /// back up after they've explicitly engaged with it.
    @State var dupeBannerDismissed: Bool = false
    /// Structural decomposition into hubs + assigned members. Computed
    /// once when the graph loads.

    // MARK: - Ingestion state

    /// Spawn point in *world* coordinates for the next-created node.
    /// `nil` → canvas picks a position (near selection or origin).
    @State var composerSpawnWorld: CGPoint?
    /// If non-nil, the composer pre-fills body with a wikilink to this id.
    @State var composerSeedID: String?
    /// After save, this is set so the canvas can pin/select/frame the
    /// newly-created node. The canvas clears it once it has consumed it.
    @State var pendingNewNode: PendingNewNode?

    /// Synthesizes a `Binding<Bool>` for sub-sheets that still
    /// expect the `isPresented:` API. The binding is `true` while
    /// `activeSheet == kind`; setting it to `false` clears
    /// `activeSheet` only if our kind is the one currently active
    /// (so a stale dismissal doesn't blow away a different sheet).
    func sheetBinding(for kind: ActiveSheet) -> Binding<Bool> {
        Binding(
            get: { activeSheet == kind },
            set: { newValue in
                if newValue {
                    activeSheet = kind
                } else if activeSheet == kind {
                    activeSheet = nil
                }
            }
        )
    }

    public init(store: GraphStore) {
        _store = StateObject(wrappedValue: store)
    }

    public init() {
        _store = StateObject(wrappedValue: GraphStore())
    }

    public var body: some View {
        canvasStack
        .onAppear { store.loadDefaultAtlas() }
        .onChange(of: store.graph.nodes.count) { _, _ in
            // Recompute duplicate clusters whenever the graph changes
            // (atlas load, create, delete, merge). Reset the dismissal
            // flag only on growth — shrinking after a merge shouldn't
            // re-pop the banner.
            let newClusters = store.duplicateClusters()
            if newClusters.count > duplicateClusters.count {
                dupeBannerDismissed = false
            }
            duplicateClusters = newClusters
        }
        .onChange(of: store.loadCompletedTick) { _, _ in
            // Atlas load arrived with content. Arm the settle gate —
            // the actual fit + fade is triggered when the canvas's
            // layout pipeline (`rebuildLayoutPipeline`) increments
            // `layoutSettleTick` below. This replaces the previous
            // heuristic sleep with a real signal, so the loading
            // screen stays up until force-atlas has actually placed
            // the nodes.
            awaitingLayoutSettle = true
        }
        .onChange(of: store.layoutSettleTick) { _, _ in
            guard awaitingLayoutSettle else { return }
            awaitingLayoutSettle = false
            Task { @MainActor in
                // Layout converged — frame the result, then start the
                // 2 s fade. The fade reveals an already-laid-out,
                // already-framed canvas.
                frameAllPulse &+= 1
                try? await Task.sleep(for: .milliseconds(400))
                store.finishLoadingPresentation()
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
        .sheet(isPresented: sheetBinding(for: .atlasSettings)) {
            AtlasSettingsSheet(store: store,
                               isPresented: sheetBinding(for: .atlasSettings))
        }
        .sheet(isPresented: sheetBinding(for: .importRecipe)) {
            ImportRecipeSheet(store: store,
                              isPresented: sheetBinding(for: .importRecipe))
        }
        .sheet(isPresented: sheetBinding(for: .templatePicker)) {
            TemplatePickerSheet(
                isPresented: sheetBinding(for: .templatePicker),
                onPick: { template in
                    pendingTemplate = template
                    activeSheet = nil
                    // Defer the folder picker one tick so the sheet
                    // dismiss animation isn't fighting the picker
                    // present animation — same Menu/sheet race we
                    // handled in `presentFolderPicker`.
                    DispatchQueue.main.async {
                        presentFolderPicker(.createNewAtlas)
                    }
                }
            )
        }
        .sheet(isPresented: sheetBinding(for: .duplicateReview)) {
            DuplicateReviewSheet(
                clusters: duplicateClusters,
                store: store,
                isPresented: sheetBinding(for: .duplicateReview),
                onSelect: { id in
                    selectedNodeID = id
                    activeSheet = nil
                }
            )
        }
        .sheet(isPresented: sheetBinding(for: .addNode)) {
            AddNodeSheet(
                store: store,
                isPresented: sheetBinding(for: .addNode),
                seedConnectionTo: composerSeedID,
                spawnWorld: composerSpawnWorld,
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
        // canvas to load it as an atlas. On iOS this is mostly useful
        // alongside Stage Manager and the system file browser; iPhone
        // users will keep using the picker.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            AtlasDropHandler.handle(providers, store: store)
        }
        .modifier(InspectorPresentation(
            isPresented: $inspectorVisible,
            useSheet: useSheetForInspector
        ) {
            inspectorContent
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
        .onChange(of: highlightDepth) { _, newValue in
            // Persist immediately so the per-atlas hop dial survives
            // a restart even if the user never triggers a new layout
            // pass (which is the only other write path).
            var snapshot = LayoutPersistence.load() ?? PersistedLayout()
            snapshot.highlightDepth = newValue
            Task.detached { LayoutPersistence.save(snapshot) }
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
    func refreshBridgeNodesIfNeeded() {
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
    /// Compact pill in the toolbar showing the atlas's current mode.
    /// Pure display today — mode is set at atlas creation via the
    /// template picker; switching modes mid-atlas is out of scope for
    /// Phase 2.
    @ViewBuilder
    var modePill: some View {
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
        .help("This atlas is in \(mode.displayName) mode.")
    }

    var useSheetForInspector: Bool {
        #if os(iOS)
        return hSizeClass == .compact
        #else
        return false
        #endif
    }

    /// Push the current selection onto the back stack before applying
    /// a new state — unless `navigation` is the one driving the
    /// change (goBack / goForward).
    func recordNavIfNeeded() {
        let now = NavigationHistory.State(selectedNodeID: selectedNodeID)
        defer { lastNavState = now }
        if navigation.suppressRecording { return }
        navigation.record(now, previous: lastNavState)
    }

    func navigateBack() {
        let now = NavigationHistory.State(selectedNodeID: selectedNodeID)
        guard let previous = navigation.goBack(from: now) else { return }
        applyNavState(previous)
    }

    func navigateForward() {
        let now = NavigationHistory.State(selectedNodeID: selectedNodeID)
        guard let next = navigation.goForward(from: now) else { return }
        applyNavState(next)
    }

    func applyNavState(_ state: NavigationHistory.State) {
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
    /// drop, which is why "Open Atlas Folder…" appeared to do nothing.
    func presentFolderPicker(_ mode: FolderPickerMode) {
        folderPickerMode = mode
        DispatchQueue.main.async {
            showingFolderPicker = true
        }
    }

    /// Route a picked folder URL based on the currently-active
    /// `folderPickerMode`. Shared between the macOS `.fileImporter`
    /// path and the iOS `FolderPicker` (UIDocumentPicker) path.
    func handleFolderPick(_ url: URL?) {
        let mode = folderPickerMode
        folderPickerMode = nil
        guard let url else { return }
        switch mode {
        case .openAtlas:
            store.load(from: url)
        case .createNewAtlas:
            // The user picked a parent folder; materialize a child
            // named after the chosen template inside it (or use the
            // chosen folder directly if it's already empty). Template
            // was selected earlier in `TemplatePickerSheet` and
            // stashed on `pendingTemplate`.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let template = pendingTemplate
            pendingTemplate = nil
            let folderName = template.map { "\($0.name) Atlas" }
                ?? "Terra Cognita Atlas"
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
            store.createNewAtlas(at: target, template: template)
        case .none:
            break
        }
    }

    /// Step 2 of GEXF import: ask the user where to materialize the
    /// new atlas. Uses NSOpenPanel directly on macOS — SwiftUI's
    /// `.fileImporter` runs into mount conflicts when fired
    /// back-to-back with another importer. On iOS this is a no-op for
    /// now; iPad GEXF import can layer on UIDocumentPicker later.
    func promptForGEXFDestination() {
        guard let doc = pendingGEXFDocument,
              let basename = pendingGEXFName else { return }
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for the imported atlas"
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


    /// Composed visible-node filter:
    ///   - Lens type filter, if any
    ///   - Private nodes (front-matter `private: true`) hidden unless
    ///     the eye-toggle is on.
    var visibleFilter: ((Node) -> Bool)? {
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

/// Modal that reviews duplicate-slug clusters found at atlas load and
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
/// per-type lenses are generated dynamically from the atlas's
/// `AtlasConfig.types` so a custom ontology surfaces correctly in the
/// picker.
struct Lens: Hashable, Identifiable {
    enum Kind: Hashable {
        case all
        case type(String)   // type name from AtlasConfig.types
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

    /// All lenses available for the active atlas: `all`, then one per
    /// declared type, then `Systems` as the topology view. Order
    /// matters for the picker.
    static func all(for config: AtlasConfig) -> [Lens] {
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

