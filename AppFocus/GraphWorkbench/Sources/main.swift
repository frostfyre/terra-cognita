import Foundation

// Construct the path to the GEXF file within the project's Data directory.
let fileManager = FileManager.default
let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let dataURL = currentDirectoryURL.appendingPathComponent("Data")
let gexfURL = dataURL.appendingPathComponent("heritage-map.gexf")

// Check if the file exists
guard fileManager.fileExists(atPath: gexfURL.path) else {
    print("Error: heritage-map.gexf not found at \(gexfURL.path)")
    exit(1)
}

// Initialize the parser with the file URL
let parser = GEXFParser(fileURL: gexfURL)

do {
    // Parse the GEXF file
    try parser.parse()
    
    // Print the results
    let graph = parser.graph
    print("Successfully parsed the GEXF file.")
    print("Number of nodes: \(graph.nodes.count)")
    print("Number of edges: \(graph.edges.count)")

    // Example: Print a few nodes to verify
    print("\n--- Example Nodes ---")
    for node in graph.nodes.values.prefix(5) {
        let nodeType = node.type ?? "N/A"
        print("Node: \(node.label) (Type: \(nodeType))")
    }
    
} catch {
    print("An error occurred during GEXF parsing: \(error)")
    exit(1)
}
