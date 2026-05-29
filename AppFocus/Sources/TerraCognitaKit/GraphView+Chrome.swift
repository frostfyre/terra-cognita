import SwiftUI

/// Top-level view composition — main `canvasStack` (canvas +
/// radial overlays + banners), the `topBar` toolbar, the Atlas
/// menu, sub-bars (duplicate banner, load status pill, search
/// overlay), the inspector content closure, and the hidden
/// keyboard-shortcut catchers we keep alive after the toolbar
/// collapse removed their visible buttons. Pure layout / chrome;
/// no behaviour lives here that isn't covered by the body.
extension GraphView {

    /// Main canvas stack — extracted from `body` so the chained
    /// modifier list outside it doesn't have to be type-checked in
    /// one expression. Layered top-to-bottom: graph canvas, radial
    /// menu (when armed), top bar, banners, and the invisible
    /// escape-catcher.
    @ViewBuilder
    var canvasStack: some View {
        ZStack(alignment: .top) {
            // Root substrate. Without this, the very first SwiftUI
            // frame on macOS shows the NSWindow's default light
            // background, and on iOS there's a perceptible white
            // gap between the launch storyboard ending and the
            // SwiftUI scene rendering. Painting the same deep
            // midnight that `LoadingScreen` uses as its gradient
            // top means the substrate is dark from frame zero.
            LoadingScreen.substrate
                .ignoresSafeArea()

            GraphCanvasView(
                store: store,
                selectedNodeID: $selectedNodeID,
                pendingNewNode: $pendingNewNode,
                visibleNodeFilter: visibleFilter,
                onLongPressEmptyWorld: { worldPoint, screenPoint in
                    globalRadial = GlobalRadialTarget(
                        world: worldPoint, screen: screenPoint)
                },
                onLongPressNode: { nodeID, screenPoint in
                    radialTarget = RadialTarget(nodeID: nodeID, point: screenPoint)
                },
                frameAllPulse: $frameAllPulse,
                layoutAlgorithm: $layoutAlgorithm,
                noOverlap: $noOverlap,
                layoutRequest: $layoutRequest,
                highlightDepth: $highlightDepth,
                connectingFromID: $connectingFromID,
                onConnectDropEmpty: { sourceID, worldPoint in
                    // Empty-canvas drop during Connect mode opens the
                    // unified Add Node sheet seeded with a wikilink to
                    // the source, spawning at the drop point. Connect
                    // mode is cleared by the canvas before the
                    // callback so the sheet doesn't compete for taps.
                    composerSpawnWorld = worldPoint
                    composerSeedID = sourceID
                    activeSheet = .addNode
                },
                bridgeNodeIDs: bridgeNodeIDs
            )
            // Fade the current atlas out while the New Atlas sheet
            // is up so the user is building a fresh map against the
            // substrate, not visually mixing it with the loaded
            // graph behind. Returns smoothly if they cancel.
            .opacity(activeSheet == .templatePicker ? 0.0 : 1.0)
            .animation(.easeInOut(duration: 0.35),
                       value: activeSheet == .templatePicker)

            // Both radials fade + shrink back toward their anchor on
            // dismiss. The bloom-out is internal to `RadialMenu`;
            // these wrapper transitions handle the unmount step
            // since the parent removes the view as soon as the
            // target binding goes nil.
            if let target = radialTarget,
               let node = store.graph.nodes[target.nodeID] {
                RadialMenu(
                    center: target.point,
                    actions: radialActions(for: node),
                    onCancel: { withAnimation(.easeOut(duration: 0.18)) { radialTarget = nil } }
                )
                .transition(.scale(scale: 0.55, anchor: .center)
                    .combined(with: .opacity))
            }

            if let target = globalRadial {
                RadialMenu(
                    center: target.screen,
                    actions: globalRadialActions(at: target),
                    onCancel: { withAnimation(.easeOut(duration: 0.18)) { globalRadial = nil } }
                )
                .transition(.scale(scale: 0.55, anchor: .center)
                    .combined(with: .opacity))
            }

            topBar

            if !duplicateClusters.isEmpty && !dupeBannerDismissed {
                duplicateBanner
            }

            if !store.loadStatus.isEmpty {
                loadStatusPill
            }

            if showingSearch {
                searchOverlay
            }

            if let caption = store.loadingCaption {
                LoadingScreen(caption: caption)
                    .transition(.opacity)
                    .zIndex(1000)
            }

            if let sourceID = connectingFromID,
               let source = store.graph.nodes[sourceID] {
                connectModeBanner(sourceLabel: source.label)
            }

            // Escape: cancel connect mode if armed, otherwise clear
            // the selection. Two separate hidden buttons so SwiftUI
            // can bind the shortcut to whichever is mounted —
            // connect-mode takes priority because Escape's primary
            // meaning while it's armed is "back out of this gesture."
            if connectingFromID != nil {
                Button("") { connectingFromID = nil }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            } else if selectedNodeID != nil {
                Button("") { selectedNodeID = nil }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }

            hiddenShortcuts
        }
    }

    @ViewBuilder
    var duplicateBanner: some View {
        VStack {
            Spacer().frame(height: 48)
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(.orange)
                Text("\(duplicateClusters.count) duplicate cluster\(duplicateClusters.count == 1 ? "" : "s") detected")
                    .font(.caption)
                Spacer()
                Button("Review") {
                    activeSheet = .duplicateReview
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

    /// Top-of-canvas banner shown while Connect mode is armed.
    /// Tells the user which node they're connecting from and how
    /// to cancel. Sits just under `topBar` so it's discoverable
    /// without obscuring the canvas content underneath.
    @ViewBuilder
    func connectModeBanner(sourceLabel: String) -> some View {
        VStack {
            Spacer().frame(height: 48)
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(.yellow)
                Text("Connect from")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sourceLabel)
                    .font(.caption.weight(.semibold))
                Text("· tap a node, or empty canvas for a new one")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    connectingFromID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Cancel connect")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.yellow.opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    var loadStatusPill: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 6) {
                    Text(store.loadStatus)
                        .font(.caption)
                    Button {
                        store.loadStatus = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }
                .padding(6)
                .background(.thinMaterial,
                            in: RoundedRectangle(cornerRadius: 6))
                .padding(8)
                Spacer()
            }
        }
    }

    @ViewBuilder
    var searchOverlay: some View {
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

    /// Collapsed top toolbar — high-frequency only. Lens / Add /
    /// Layout / Fit / Private moved to the canvas radial wheels
    /// (long-press blank for the global wheel, long-press a node
    /// for the per-node one). What stays here is navigation + the
    /// affordances the user wants at the periphery while reading:
    /// back / forward, mode, atlas, find, inspector.
    @ViewBuilder
    var topBar: some View {
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
            modePill
            Spacer()
            atlasMenu

            Button {
                showingSearch = true
            } label: {
                Label("Find", systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("f", modifiers: .command)
            .help("Find a node by name (⌘F)")

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
    }

    /// Zero-size keyboard-shortcut catchers for affordances we
    /// pulled out of the toolbar. SwiftUI binds `.keyboardShortcut`
    /// to the visible button — so when the buttons left, so did
    /// the shortcuts. These hidden buttons restore them.
    @ViewBuilder
    var hiddenShortcuts: some View {
        Group {
            Button("") {
                frameAllPulse &+= 1
            }
            .keyboardShortcut("0", modifiers: .command)

            // Both shortcuts open the unified Add Node sheet. ⌘N seeds
            // a connection to the current selection; ⌘⇧N opens unseeded
            // — useful when you want a standalone node from text capture.
            Button("") {
                guard store.canIngest else { return }
                composerSpawnWorld = nil
                composerSeedID = selectedNodeID
                activeSheet = .addNode
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("") {
                guard store.canIngest else { return }
                composerSpawnWorld = nil
                composerSeedID = nil
                activeSheet = .addNode
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    @ViewBuilder
    var atlasMenu: some View {
        Menu {
            Button {
                presentFolderPicker(.openAtlas)
            } label: {
                Label("Open Atlas Folder…", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            Button {
                activeSheet = .templatePicker
            } label: {
                Label("Create New Atlas…", systemImage: "folder.badge.plus")
            }
            Button {
                showingGEXFPicker = true
            } label: {
                Label("Import GEXF…", systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                activeSheet = .importRecipe
            } label: {
                Label("Import from Recipe…", systemImage: "wand.and.stars")
            }
            Divider()
            Button {
                activeSheet = .atlasSettings
            } label: {
                Label("Atlas Settings…", systemImage: "gearshape")
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
                store.resetToDefaultAtlas()
            } label: {
                Label("Use Default (Miyazaki)", systemImage: "sparkles")
            }
        } label: {
            Label("Atlas", systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Open a markdown atlas folder (⌘O)")
    }

    /// Inspector body, factored out of `body` so SwiftUI's type
    /// inference doesn't have to chew through the whole graph view
    /// in one pass.
    @ViewBuilder
    var inspectorContent: some View {
        if let id = selectedNodeID {
            NodeInspectorView(
                nodeID: id,
                store: store,
                onSelectNode: { newID in selectedNodeID = newID },
                pendingIntent: $pendingInspectorIntent
            )
        } else {
            ContentUnavailableView(
                "No node selected",
                systemImage: "circle.dashed",
                description: Text("Tap a node in the graph to inspect it.")
            )
        }
    }

}
