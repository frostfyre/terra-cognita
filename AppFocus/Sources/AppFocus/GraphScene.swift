#if os(macOS)
import SpriteKit
import SwiftUI

class GraphScene: SKScene {
    let graph: HeritageGraph
    var viewModel: GraphViewModel
    private var selectedSKNode: SKNode?
    private var edgeNodes: [EdgeNode] = []
    private var draggingScene = false
    private var lastMousePosition: CGPoint?
    
    // Add a camera for panning
    private let cameraNode = SKCameraNode()

    init(graph: HeritageGraph, viewModel: GraphViewModel) {
        self.graph = graph
        self.viewModel = viewModel
        super.init(size: .zero)
        self.camera = cameraNode
        self.addChild(cameraNode)
        print("GraphScene initialized.")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        
        self.size = view.bounds.size
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        
        print("GraphScene didMove(to:) view with size \(view.bounds.size)")
        
        self.backgroundColor = .white

        print("Graph data received with \(graph.nodes.count) nodes and \(graph.edges.count) edges.")
        addNodes(for: graph)
        addEdges(for: graph)
        
        print("GraphScene finished didMove(to:)")
    }

    private func addNodes(for graph: HeritageGraph) {
        print("Adding \(graph.nodes.count) nodes to the scene...")
        for (i, node) in graph.nodes.values.enumerated() {
            let nodeSprite = SKSpriteNode(color: .systemBlue, size: CGSize(width: 30, height: 30))
            nodeSprite.name = node.id
            nodeSprite.position = CGPoint(x: Int.random(in: 0...Int(self.size.width)), y: Int.random(in: 0...Int(self.size.height)))
            nodeSprite.isUserInteractionEnabled = true
            nodeSprite.zPosition = 1
            
            if i == 0 {
                print("First node position: \(nodeSprite.position)")
            }
            
            self.addChild(nodeSprite)
            
            if i % 100 == 0 {
                print("Added \(i) nodes...")
            }
        }
        print("Finished adding nodes.")
    }

    private func addEdges(for graph: HeritageGraph) {
        print("Adding \(graph.edges.count) edges to the scene...")
        for (i, edge) in graph.edges.enumerated() {
            guard let sourceNode = self.childNode(withName: edge.sourceID) as? SKSpriteNode,
                  let targetNode = self.childNode(withName: edge.targetID) as? SKSpriteNode else {
                continue
            }
            
            let edgeNode = EdgeNode()
            edgeNode.sourceNode = sourceNode
            edgeNode.targetNode = targetNode
            edgeNode.strokeColor = .gray
            edgeNode.lineWidth = 1.5
            edgeNode.updatePath()
            self.addChild(edgeNode)
            edgeNodes.append(edgeNode)
            
            if i % 100 == 0 {
                print("Added \(i) edges...")
            }
        }
        print("Finished adding edges.")
    }

    private func createSelectionIndicator() -> SKShapeNode {
        let selectionIndicator = SKShapeNode(circleOfRadius: 20)
        selectionIndicator.strokeColor = .green
        selectionIndicator.lineWidth = 2
        selectionIndicator.name = "selectionIndicator"
        return selectionIndicator
    }

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        lastMousePosition = location
        print("mouseDown at \(location)")

        if let node = self.atPoint(location) as? SKSpriteNode, let nodeName = node.name {
            if let graphNode = graph.getNode(byID: nodeName) {
                viewModel.startDragging(node: graphNode)
                selectedSKNode = node
                let selectionIndicator = createSelectionIndicator()
                node.addChild(selectionIndicator)
            }
        } else {
            draggingScene = true
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)
        if let selectedNode = selectedSKNode {
            selectedNode.position = location
        } else if draggingScene {
            guard let lastMousePosition = lastMousePosition else { return }
            let dx = location.x - lastMousePosition.x
            let dy = location.y - lastMousePosition.y
            cameraNode.position.x -= dx
            cameraNode.position.y -= dy
            self.lastMousePosition = location
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if let selectedNode = selectedSKNode {
            print("Released node: \(selectedNode.name ?? "unnamed")")
            selectedNode.childNode(withName: "selectionIndicator")?.removeFromParent()
            self.selectedSKNode = nil
            viewModel.stopDragging()
        }
        draggingScene = false
        lastMousePosition = nil
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        print("rightMouseDown at \(location)")

        if let node = self.atPoint(location) as? SKSpriteNode, let nodeName = node.name {
            if let graphNode = graph.getNode(byID: nodeName) {
                viewModel.handleNodeRightClick(graphNode)
            }
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        for edgeNode in edgeNodes {
            edgeNode.updatePath()
        }
    }
}
#endif
