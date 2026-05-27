import Foundation
import SwiftUI

/// A starting configuration for a new vault. Each template belongs to
/// one `Mode` and provides a default node-type vocabulary, optional
/// era taxonomy, and the subfolders to materialize. `VaultWriter`
/// consumes templates during `initializeEmptyVault(at:template:)`.
///
/// Phase 2 ships a thin registry — just type + era presets. Richer
/// template content (seed nodes, prompts, lens defaults) is a Phase 3
/// follow-up.
struct Template: Identifiable {
    let id: String
    let name: String
    let mode: Mode
    let systemImage: String
    let summary: String
    let types: [VaultConfig.TypeSpec]
    let eras: [VaultConfig.EraSpec]

    /// The subfolder names a fresh vault should pre-create.
    /// Derived from any non-nil `folder` on the template's types.
    var subfolders: [String] {
        Array(Set(types.compactMap { $0.folder })).sorted()
    }

    // MARK: - Registry

    /// All shipped templates, grouped under their modes. Order matters
    /// for the picker — first template per mode is the "starter" the
    /// user sees first.
    static let all: [Template] = [
        // ---------- Continuity ----------
        Template(
            id: "heritage",
            name: "Heritage",
            mode: .continuity,
            systemImage: "tree",
            summary: "Personal influence archaeology — the people, works, and institutions that shaped you.",
            types: continuityCoreTypes,
            eras: heritageEras
        ),
        Template(
            id: "reflective-journal",
            name: "Reflective Journal",
            mode: .continuity,
            systemImage: "book.pages",
            summary: "Temporal self-observation — journals, photos, recurring themes.",
            types: continuityCoreTypes,
            eras: yearBasedEras
        ),
        Template(
            id: "career-map",
            name: "Career Map",
            mode: .continuity,
            systemImage: "briefcase",
            summary: "Career continuity, projects, pivots, collaborators.",
            types: continuityCoreTypes,
            eras: yearBasedEras
        ),
        Template(
            id: "story-bible",
            name: "Story Bible",
            mode: .continuity,
            systemImage: "books.vertical",
            summary: "Character arcs, motifs, narrative continuity for a long work.",
            types: continuityCoreTypes,
            eras: storyEras
        ),

        // ---------- Worldbuild ----------
        Template(
            id: "world-bible",
            name: "World Bible",
            mode: .worldbuild,
            systemImage: "globe.europe.africa",
            summary: "TTRPG / novel / transmedia setting — characters, factions, places, myths.",
            types: worldbuildTypes,
            eras: []
        ),
        Template(
            id: "concept-explorer",
            name: "Concept Explorer",
            mode: .worldbuild,
            systemImage: "circle.hexagongrid",
            summary: "External-topic seed. Name a topic; the AI proposes a starter graph for you to prune.",
            types: worldbuildTypes,
            eras: []
        ),

        // ---------- Project Archaeology ----------
        Template(
            id: "markdown-vault",
            name: "Markdown Vault",
            mode: .projectArchaeology,
            systemImage: "doc.text",
            summary: "Existing notes vault — wikilinks, backlinks, recurring themes.",
            types: projectMarkdownTypes,
            eras: []
        ),
        Template(
            id: "code-repo",
            name: "Code Repo",
            mode: .projectArchaeology,
            systemImage: "chevron.left.forwardslash.chevron.right",
            summary: "Source repository — imports, classes, dependencies. (Importer arrives in Phase 3.)",
            types: projectCodeTypes,
            eras: []
        ),
    ]

    static func templates(for mode: Mode) -> [Template] {
        all.filter { $0.mode == mode }
    }

    static func byID(_ id: String?) -> Template? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static var defaultTemplate: Template { all[0] }   // Heritage
}

// MARK: - Type vocabularies

private let continuityCoreTypes: [VaultConfig.TypeSpec] = [
    .init(name: "person",      color: .cyan,   icon: "person.fill",     folder: "people"),
    .init(name: "concept",     color: .yellow, icon: "lightbulb.fill",  folder: "concepts"),
    .init(name: "institution", color: .mint,   icon: "building.2.fill", folder: "institutions"),
    .init(name: "event",       color: .orange, icon: "calendar",        folder: "events"),
    .init(name: "work",        color: .pink,   icon: "book.fill",       folder: "works"),
]

private let worldbuildTypes: [VaultConfig.TypeSpec] = [
    .init(name: "character",   color: .cyan,    icon: "person.fill",         folder: "characters"),
    .init(name: "faction",     color: .indigo,  icon: "person.3.fill",       folder: "factions"),
    .init(name: "place",       color: .mint,    icon: "mappin.and.ellipse",  folder: "places"),
    .init(name: "myth",        color: .purple,  icon: "sparkles",            folder: "myths"),
    .init(name: "institution", color: .teal,    icon: "building.2.fill",     folder: "institutions"),
    .init(name: "theme",       color: .yellow,  icon: "lightbulb.fill",      folder: "themes"),
    .init(name: "artifact",    color: .brown,   icon: "shippingbox.fill",    folder: "artifacts"),
]

private let projectMarkdownTypes: [VaultConfig.TypeSpec] = [
    .init(name: "note",        color: .cyan,    icon: "doc.text.fill",       folder: "notes"),
    .init(name: "concept",     color: .yellow,  icon: "lightbulb.fill",      folder: "concepts"),
    .init(name: "reference",   color: .indigo,  icon: "link",                folder: "references"),
]

private let projectCodeTypes: [VaultConfig.TypeSpec] = [
    .init(name: "module",      color: .cyan,   icon: "shippingbox.fill",            folder: "modules"),
    .init(name: "class",       color: .mint,   icon: "square.stack.3d.up.fill",     folder: "classes"),
    .init(name: "function",    color: .yellow, icon: "function",                    folder: "functions"),
    .init(name: "dependency",  color: .indigo, icon: "arrow.triangle.merge",        folder: "dependencies"),
]

// MARK: - Era taxonomies

private let heritageEras: [VaultConfig.EraSpec] = [
    .init(name: "pre-conscious",           weight: 0),
    .init(name: "self-choosing-childhood", weight: 1),
    .init(name: "early-formation",         weight: 2),
    .init(name: "early-career",            weight: 3),
    .init(name: "bridge",                  weight: 4),
    .init(name: "current",                 weight: 5),
    .init(name: "career-spanning",         weight: 4.5),
]

private let yearBasedEras: [VaultConfig.EraSpec] = [
    .init(name: "early",   weight: 0),
    .init(name: "mid",     weight: 1),
    .init(name: "recent",  weight: 2),
    .init(name: "current", weight: 3),
]

private let storyEras: [VaultConfig.EraSpec] = [
    .init(name: "backstory",    weight: 0),
    .init(name: "act-one",      weight: 1),
    .init(name: "act-two",      weight: 2),
    .init(name: "act-three",    weight: 3),
    .init(name: "denouement",   weight: 4),
]
