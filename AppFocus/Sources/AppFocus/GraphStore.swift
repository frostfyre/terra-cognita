import Foundation
import SwiftUI

// Minimal graph container that GraphCanvasView expects.
@MainActor
public final class GraphStore: ObservableObject {
    @Published var graph: Graph
    @Published var loadStatus: String = ""

    /// Empty store. The app's `GraphView` calls `loadDefaultVault()` to
    /// populate it from the heritage vault on disk.
    public init() {
        self.graph = Graph(nodes: [:], edges: [])
    }

    init(graph: Graph) {
        self.graph = graph
    }

    /// Loads the default heritage vault from disk. Parsing happens off the
    /// main actor; the resulting `Graph` is republished on completion.
    func loadDefaultVault() {
        Task {
            do {
                let (vaultName, g) = try await Self.loadFromDefaultVault()
                self.graph = g
                self.loadStatus = "Loaded \(g.nodes.count) nodes / \(g.edges.count) edges from \(vaultName)"
                print("[VaultLoader] \(self.loadStatus)")
            } catch VaultError.notFound {
                self.loadStatus = "Vault not found — looked relative to CWD and the executable directory."
                print("[VaultLoader] \(self.loadStatus)")
            } catch {
                self.loadStatus = "Vault load failed: \(error.localizedDescription)"
                print("[VaultLoader] \(self.loadStatus)")
            }
        }
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
