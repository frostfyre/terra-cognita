import SpriteKit

class EdgeNode: SKShapeNode {
    var sourceNode: SKNode?
    var targetNode: SKNode?

    func updatePath() {
        guard let sourceNode = sourceNode, let targetNode = targetNode else {
            return
        }

        let newPath = CGMutablePath()
        newPath.move(to: sourceNode.position)
        newPath.addLine(to: targetNode.position)
        self.path = newPath
    }
}
