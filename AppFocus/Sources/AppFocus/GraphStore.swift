import Foundation
import SwiftUI

// Minimal graph container that GraphCanvasView expects.
@MainActor
public final class GraphStore: ObservableObject {
    @Published var graph: Graph
    @Published var loadStatus: String = ""
    /// Recent vaults the user has opened. Mutated when a load
    /// succeeds; persisted to UserDefaults.
    @Published var library: VaultLibrary

    /// Empty store. The app's `GraphView` calls `loadDefaultVault()` to
    /// populate it from the heritage vault on disk.
    public init() {
        self.graph = Graph(nodes: [:], edges: [])
        self.library = VaultLibrary.load()
    }

    init(graph: Graph) {
        self.graph = graph
        self.library = VaultLibrary.load()
    }

    /// Loads the default vault: previously-bookmarked user folder if
    /// one is saved, otherwise the bundled Miyazaki demo, otherwise the
    /// development heritage vault on disk.
    func loadDefaultVault() {
        if let url = VaultBookmark.load() {
            load(from: url, fromBookmark: true)
        } else {
            Task {
                do {
                    let (vaultName, g) = try await Self.loadFromDefaultVault()
                    self.graph = g
                    self.loadStatus = "Loaded \(g.nodes.count) nodes / \(g.edges.count) edges from \(vaultName)"
                } catch VaultError.notFound {
                    self.loadStatus = "Vault not found — looked relative to CWD and the executable directory."
                } catch {
                    self.loadStatus = "Vault load failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Load a vault from a user-chosen folder URL. Manages the
    /// security-scoped resource, saves a current-vault bookmark, and
    /// touches the recent-vaults library.
    func load(from url: URL, fromBookmark: Bool = false) {
        let didStart = url.startAccessingSecurityScopedResource()
        Task {
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let g = try await Task.detached(priority: .userInitiated) {
                    try VaultLoader(vaultURL: url).load()
                }.value
                self.graph = g
                self.loadStatus = "Loaded \(g.nodes.count) nodes / \(g.edges.count) edges from \(url.lastPathComponent)"
                if !fromBookmark {
                    VaultBookmark.save(url)
                }
                self.library.touch(url,
                                   nodeCount: g.nodes.count,
                                   edgeCount: g.edges.count)
                self.library.save()
            } catch {
                self.loadStatus = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Open a recent-vaults library entry. Resolves the saved bookmark
    /// and routes through `load(from:)`.
    func openLibraryEntry(_ entryID: UUID) {
        if let url = library.resolve(entryID: entryID) {
            library.save()
            load(from: url)
        } else {
            loadStatus = "Couldn't resolve that vault — the folder may have moved."
            library.remove(entryID: entryID)
            library.save()
        }
    }

    /// Drop an entry from the recent-vaults library.
    func forgetLibraryEntry(_ entryID: UUID) {
        library.remove(entryID: entryID)
        library.save()
    }

    /// Forget the user-chosen vault and revert to the default search.
    func resetToDefaultVault() {
        VaultBookmark.clear()
        loadDefaultVault()
    }

    private enum VaultError: Error { case notFound }

    /// Non-isolated worker — runs on a background thread when awaited.
    private static func loadFromDefaultVault() async throws -> (String, Graph) {
        guard let vaultURL = VaultLoader.defaultVault() else {
            throw VaultError.notFound
        }
        let loader = VaultLoader(vaultURL: vaultURL)
        let g = try loader.load()
        return (vaultURL.lastPathComponent, g)
    }
}

// Lightweight graph model used by GraphStore.
// Matches usage in GraphCanvasView: `graph.nodes.values` and `graph.edges`
// with `Edge.id`, `Edge.sourceID`, `Edge.targetID`, `Edge.provenance`.
struct Graph {
    var nodes: [String: Node]
    var edges: [Edge]
}

// NOTE: We assume `Node` and `Edge` are defined elsewhere in the project.
// If they are not, you can uncomment the placeholder definitions below to make the project compile,
// and then replace them with your real models when ready.

/*
struct Node: Identifiable, Hashable {
    var id: String
    var label: String
    var type: String
}

struct Edge: Identifiable, Hashable {
    var id: String
    var sourceID: String
    var targetID: String
    var provenance: Provenance?
}

enum Provenance: String, Codable, CaseIterable, Hashable {
    case directInfluence
    case verifiedLineage
    case institutionalConnection
    case inferredAffinity
    case recommendation
    case adjacency
    case speculation
}
*/
