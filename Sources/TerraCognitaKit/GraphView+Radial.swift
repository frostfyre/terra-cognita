import SwiftUI

/// Radial menu action builders. Two flavours: per-node radial
/// (long-press a node — Open / AI ▸ / Edit ▸ / Center / Hops ▸)
/// and the global radial (long-press blank canvas — Add ▸ /
/// Layout ▸ / Lens ▸ / View ▸). Sub-menus are themselves arrays
/// of `RadialMenu.Action`, so the recursion lives in this file
/// alone.
extension GraphView {


    /// Compose the per-node radial menu. Top level reads as
    /// **Open · AI ▸ · Edit ▸ · Center · Hops ▸**; AI and Edit are
    /// nested sub-menus that swap in when tapped. Every terminal
    /// wedge dismisses the wheel by clearing `radialTarget`.
    func radialActions(for node: Node) -> [RadialMenu.Action] {
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

        if store.canIngest {
            actions.append(RadialMenu.Action(
                id: "connect",
                label: "Connect",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                tint: .yellow
            ) {
                // Arm spatial Connect mode. The canvas's tap handler
                // takes over from here — next tap on a node creates an
                // edge, next tap on empty canvas opens AddNodeSheet
                // seeded from this source. Escape / second tap on the
                // source cancels.
                connectingFromID = node.id
                selectedNodeID = node.id
                radialTarget = nil
            })
        }

        actions.append(RadialMenu.Action(
            id: "ai",
            label: "AI",
            systemImage: "sparkles",
            tint: .indigo,
            children: aiSubActions(for: node)
        ))

        if store.canIngest {
            actions.append(RadialMenu.Action(
                id: "edit",
                label: "Edit",
                systemImage: "pencil",
                tint: .orange,
                children: editSubActions(for: node)
            ))
        }

        actions.append(RadialMenu.Action(
            id: "center",
            label: "Center",
            systemImage: "scope",
            tint: .teal
        ) {
            selectedNodeID = node.id
            radialTarget = nil
        })

        actions.append(RadialMenu.Action(
            id: "hops",
            label: "Hops",
            systemImage: "dot.radiowaves.left.and.right",
            tint: .pink,
            children: hopsSubActions(onPick: { radialTarget = nil })
        ))

        return actions
    }

    /// Five AI wedges — each routes through the inspector's
    /// `NodeIntelligence` instance via `pendingInspectorIntent`.
    func aiSubActions(for node: Node) -> [RadialMenu.Action] {
        let dispatch: (NodeIntelligence.Operation) -> Void = { op in
            selectedNodeID = node.id
            inspectorVisible = true
            pendingInspectorIntent = .aiOperation(op)
            radialTarget = nil
        }
        return [
            RadialMenu.Action(
                id: "ai-connect",
                label: "Connections",
                systemImage: NodeIntelligence.Operation.suggestConnect.icon,
                tint: .indigo
            ) { dispatch(.suggestConnect) },
            RadialMenu.Action(
                id: "ai-links",
                label: "Find links",
                systemImage: NodeIntelligence.Operation.findLinks.icon,
                tint: .indigo
            ) { dispatch(.findLinks) },
            RadialMenu.Action(
                id: "ai-era",
                label: "Suggest era",
                systemImage: NodeIntelligence.Operation.suggestEra.icon,
                tint: .indigo
            ) { dispatch(.suggestEra) },
            RadialMenu.Action(
                id: "ai-concepts",
                label: "Concepts",
                systemImage: NodeIntelligence.Operation.extractConcepts.icon,
                tint: .indigo
            ) { dispatch(.extractConcepts) },
            RadialMenu.Action(
                id: "ai-rewrite",
                label: "Rewrite",
                systemImage: NodeIntelligence.Operation.rewriteConcise.icon,
                tint: .indigo
            ) { dispatch(.rewriteConcise) },
        ]
    }

    /// Edit-time affordances. Type / Era live in the header so the
    /// wedge simply opens the inspector — the user taps the pill
    /// from there. Body / Merge route through `pendingInspectorIntent`
    /// to land the inspector in the right state. Delete is direct.
    func editSubActions(for node: Node) -> [RadialMenu.Action] {
        let openInspector: () -> Void = {
            selectedNodeID = node.id
            inspectorVisible = true
            radialTarget = nil
        }
        return [
            RadialMenu.Action(
                id: "edit-type",
                label: "Type",
                systemImage: "tag",
                tint: .orange
            ) { openInspector() },
            RadialMenu.Action(
                id: "edit-era",
                label: "Era",
                systemImage: "calendar.badge.clock",
                tint: .orange
            ) { openInspector() },
            RadialMenu.Action(
                id: "edit-body",
                label: "Body",
                systemImage: "text.alignleft",
                tint: .orange
            ) {
                selectedNodeID = node.id
                inspectorVisible = true
                pendingInspectorIntent = .editBody
                radialTarget = nil
            },
            RadialMenu.Action(
                id: "edit-merge",
                label: "Merge…",
                systemImage: "arrow.triangle.merge",
                tint: .orange
            ) {
                selectedNodeID = node.id
                inspectorVisible = true
                pendingInspectorIntent = .showMergePicker
                radialTarget = nil
            },
            RadialMenu.Action(
                id: "edit-delete",
                label: "Delete",
                systemImage: "trash",
                tint: .red
            ) {
                _ = store.deleteNode(node.id)
                if selectedNodeID == node.id { selectedNodeID = nil }
                radialTarget = nil
            },
        ]
    }

    /// Four hop-distance wedges. The active value shows a ✓ badge
    /// so the user can read the current state at a glance. The
    /// `onPick` callback runs *after* the depth is updated, so the
    /// caller can dismiss whichever radial it lives inside (per-node
    /// vs global).
    func hopsSubActions(onPick: @escaping () -> Void) -> [RadialMenu.Action] {
        (1...4).map { depth in
            RadialMenu.Action(
                id: "hops-\(depth)",
                label: "\(depth) hop\(depth == 1 ? "" : "s")",
                systemImage: "\(depth).circle",
                tint: .pink,
                isChecked: highlightDepth == depth
            ) {
                highlightDepth = depth
                onPick()
            }
        }
    }

    // MARK: - Global radial (long-press empty canvas)

    /// Top-level wedges for the canvas-level radial.
    ///   Add ▸  · Layout ▸ · Lens ▸ · View ▸
    /// All terminal actions clear `globalRadial` to dismiss the wheel.
    func globalRadialActions(at target: GlobalRadialTarget) -> [RadialMenu.Action] {
        [
            RadialMenu.Action(
                id: "g-add",
                label: "Add",
                systemImage: "plus.circle",
                tint: .green,
                children: addSubActions(at: target)
            ),
            RadialMenu.Action(
                id: "g-layout",
                label: "Layout",
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: .blue,
                children: layoutSubActions()
            ),
            RadialMenu.Action(
                id: "g-lens",
                label: "Lens",
                systemImage: "camera.aperture",
                tint: .indigo,
                children: lensSubActions()
            ),
            RadialMenu.Action(
                id: "g-view",
                label: "View",
                systemImage: "rectangle.on.rectangle",
                tint: .teal,
                children: viewSubActions()
            ),
        ]
    }

    func addSubActions(at target: GlobalRadialTarget) -> [RadialMenu.Action] {
        var actions: [RadialMenu.Action] = [
            RadialMenu.Action(
                id: "add-node",
                label: "Add node",
                systemImage: "circle.dashed.inset.filled",
                tint: .green
            ) {
                globalRadial = nil
                guard store.canIngest else { return }
                composerSpawnWorld = target.world
                composerSeedID = selectedNodeID
                activeSheet = .addNode
            },
        ]
        // "Recipe" import is temporarily pulled from the UI — see
        // GraphView.recipeImportEnabled.
        if Self.recipeImportEnabled {
            actions.append(RadialMenu.Action(
                id: "add-recipe",
                label: "Recipe",
                systemImage: "wand.and.stars",
                tint: .green
            ) {
                globalRadial = nil
                activeSheet = .importRecipe
            })
        }
        return actions
    }

    /// One wedge per `LayoutAlgorithm`, plus a No-overlap toggle.
    /// Implemented algorithms commit immediately; unimplemented ones
    /// surface but are non-committing (no-op tap).
    func layoutSubActions() -> [RadialMenu.Action] {
        var actions: [RadialMenu.Action] = LayoutAlgorithm.allCases.map { algo in
            RadialMenu.Action(
                id: "layout-\(algo.rawValue)",
                label: algo.displayName,
                systemImage: algo.systemImage,
                tint: .blue,
                isChecked: layoutAlgorithm == algo
            ) {
                if algo.isImplemented {
                    layoutRequest = algo
                }
                globalRadial = nil
            }
        }
        actions.append(RadialMenu.Action(
            id: "layout-no-overlap",
            label: "No overlap",
            systemImage: "rectangle.dashed",
            tint: .blue,
            isChecked: noOverlap
        ) {
            noOverlap.toggle()
            globalRadial = nil
        })
        return actions
    }

    /// Lens wedges — one per declared type plus All / Systems.
    /// Count badges are baked into the label so the user sees the
    /// same surface-area at a glance as the old toolbar picker.
    func lensSubActions() -> [RadialMenu.Action] {
        Lens.all(for: store.config).enumerated().map { i, lens in
            let count: Int? = {
                guard let filter = lens.makeTypeFilter() else { return nil }
                return store.graph.nodes.values.filter(filter).count
            }()
            let labelText = count.map { "\(lens.label) (\($0))" } ?? lens.label
            return RadialMenu.Action(
                id: "lens-\(i)",
                label: labelText,
                systemImage: lens.icon,
                tint: .indigo,
                isChecked: activeLens == lens
            ) {
                activeLens = lens
                globalRadial = nil
            }
        }
    }

    /// View toggles + the global hop dial (mirror of the per-node
    /// Hops submenu so the user can set their default highlight
    /// radius without selecting a node first).
    func viewSubActions() -> [RadialMenu.Action] {
        [
            RadialMenu.Action(
                id: "view-inspector",
                label: "Inspector",
                systemImage: inspectorVisible ? "sidebar.right" : "sidebar.squares.right",
                tint: .teal,
                isChecked: inspectorVisible
            ) {
                inspectorVisible.toggle()
                globalRadial = nil
            },
            RadialMenu.Action(
                id: "view-private",
                label: "Private",
                systemImage: showPrivate ? "eye.fill" : "eye.slash",
                tint: .teal,
                isChecked: showPrivate
            ) {
                showPrivate.toggle()
                globalRadial = nil
            },
            RadialMenu.Action(
                id: "view-fit",
                label: "Fit",
                systemImage: "viewfinder",
                tint: .teal
            ) {
                frameAllPulse &+= 1
                globalRadial = nil
            },
            RadialMenu.Action(
                id: "view-hops",
                label: "Hops",
                systemImage: "dot.radiowaves.left.and.right",
                tint: .pink,
                children: hopsSubActions(onPick: { globalRadial = nil })
            ),
        ]
    }

}
