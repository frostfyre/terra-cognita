
import Foundation
import SwiftUI

class GraphViewModel: ObservableObject {
    @Published var selectedNode: Node?
    @Published var rightClickedNode: Node? {
        didSet {
            if let node = rightClickedNode {
                loadMarkdown(for: node)
            } else {
                selectedMarkdownContent = nil
            }
        }
    }
    @Published var graph = HeritageGraph()
    @Published var draggingNode: Node?
    @Published var isDragging = false
    @Published var selectedMarkdownContent: String?

    init() {
        print("GraphViewModel initialized.")
        loadGraphData()
    }

    private func loadGraphData() {
        print("Attempting to load graph data...")
        guard let url = Bundle.main.url(forResource: "heritage-map", withExtension: "gexf", subdirectory: "Data") else {
            print("Error: Could not find heritage-map.gexf in the bundle.")
            return
        }
        print("Found GEXF file at URL: \(url)")
        let parser = GEXFParser(fileURL: url)
        do {
            try parser.parse()
            self.graph = parser.graph
            print("Graph loaded with \(self.graph.nodes.count) nodes and \(self.graph.edges.count) edges.")
        } catch {
            print("Error parsing GEXF: \(error)")
        }
    }

    func handleNodeClick(_ node: Node) {
        selectedNode = node
    }

    func handleNodeRightClick(_ node: Node) {
        rightClickedNode = node
    }

    func startDragging(node: Node) {
        draggingNode = node
        isDragging = true
    }

    func stopDragging() {
        draggingNode = nil
        isDragging = false
    }
    
    func loadMarkdown(for node: Node) {
        guard let relativePath = node.filePath else {
            self.selectedMarkdownContent = "No markdown file associated with \(node.label)"
            return
        }
        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let vaultURL = currentDirectoryURL.appendingPathComponent("Data/heritage-vault/heritage-vault")
        let markdownURL = vaultURL.appendingPathComponent(relativePath)

        do {
            self.selectedMarkdownContent = try String(contentsOf: markdownURL)
        } catch {
            print("Error loading markdown for node \(node.id): \(error)")
            self.selectedMarkdownContent = "Could not load content for \(node.label)"
        }
    }
}
