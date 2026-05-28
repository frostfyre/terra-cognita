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
                bridgeNodeIDs: bridgeNodeIDs
            )

            if let target = radialTarget,
               let node = store.graph.nodes[target.nodeID] {
                RadialMenu(
                    center: target.point,
                    actions: radialActions(for: node),
                    onCancel: { radialTarget = nil }
                )
                .transition(.opacity)
            }

            if let target = globalRadial {
                RadialMenu(
                    center: target.screen,
                    actions: globalRadialActions(at: target),
                    onCancel: { globalRadial = nil }
                )
                .transition(.opacity)
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
                loadingOverlay(caption: caption)
            }

            if selectedNodeID != nil {
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

    @ViewBuilder
    var loadStatusPill: some View {
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

    /// Centered overlay with a spinner + the rotating caption from
    /// `LoadingCaptions`. Sits above everything except the radial
    /// menus (we won't render radials during a load anyway since
    /// the canvas content is still arriving). The dimmer is
    /// non-blocking — gestures still pass through — but the caption
    /// gives the user something to read instead of a frozen frame.
    @ViewBuilder
    func loadingOverlay(caption: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.regular)
                    .tint(.white)
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .animation(.easeInOut(duration: 0.4), value: caption)
                    .transition(.opacity)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.55))
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
        .id(caption)   // force the .transition on each new caption
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

            Button("") {
                guard store.canIngest else { return }
                composerSpawnWorld = nil
                composerSeedID = selectedNodeID
                activeSheet = .composer
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("") {
                guard store.canIngest else { return }
                activeSheet = .capture
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
