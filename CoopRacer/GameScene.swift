import SpriteKit

final class GameScene: SKScene {
    enum Side { case left, right }

    private let side: Side
    private weak var input: PlayerInput?

    private let carNode = SKNode()          // composed car
    private var laneWidth: CGFloat { size.width * 0.40 }
    private var speedY: CGFloat = 240
    private var lastUpdate: TimeInterval = 0

    init(size: CGSize, side: Side, input: PlayerInput) {
        self.side = side
        self.input = input
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        removeAllChildren()
        carNode.removeAllChildren()
        addChild(carNode)

        // Track boundaries (simple guide rails)
        let inner = SKShapeNode(rectOf: CGSize(width: size.width * 0.70, height: size.height * 0.90), cornerRadius: 8)
        inner.strokeColor = side == .left ? .red : .blue
        inner.lineWidth = 2
        inner.alpha = 0.7
        inner.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(inner)

        buildCarShape()

        // Place car
        carNode.position = CGPoint(x: size.width/2, y: size.height * 0.25)

        // Scrolling lane markers
        for i in 0..<14 {
            addLaneDash(y: CGFloat(i) * 70.0)
        }

        lastUpdate = 0
    }

    private func buildCarShape() {
        let accent: SKColor = (side == .left) ? .red : .blue

        // Body (rounded rectangle)
        let body = SKShapeNode(rectOf: CGSize(width: 26, height: 44), cornerRadius: 9)
        body.fillColor = accent
        body.strokeColor = .clear
        body.zPosition = 1

        // Wheels (dark rounded rectangles)
        func wheel(offsetX: CGFloat, offsetY: CGFloat) -> SKShapeNode {
            let w = SKShapeNode(rectOf: CGSize(width: 6, height: 12), cornerRadius: 3)
            w.fillColor = .black.withAlphaComponent(0.85)
            w.strokeColor = .clear
            w.position = CGPoint(x: offsetX, y: offsetY)
            w.zPosition = 2
            return w
        }
        let wheels = [
            wheel(offsetX: -10, offsetY: 12),  // front-left
            wheel(offsetX:  10, offsetY: 12),  // front-right
            wheel(offsetX: -10, offsetY: -12), // rear-left
            wheel(offsetX:  10, offsetY: -12), // rear-right
        ]

        // Windshield
        let wsPath = CGPath(roundedRect: CGRect(x: -9, y: 8, width: 18, height: 10), cornerWidth: 3, cornerHeight: 3, transform: nil)
        let windshield = SKShapeNode(path: wsPath)
        windshield.fillColor = .white.withAlphaComponent(0.85)
        windshield.strokeColor = .clear
        windshield.zPosition = 3

        // Assemble
        carNode.addChild(body)
        wheels.forEach { carNode.addChild($0) }
        carNode.addChild(windshield)
    }

    private func addLaneDash(y: CGFloat) {
        let path = CGMutablePath()
        let x = size.width/2
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x, y: y + 35))
        let dash = SKShapeNode(path: path)
        dash.strokeColor = .white
        dash.lineWidth = 2
        dash.name = "dash"
        addChild(dash)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Rebuild layout on size changes
        if view != nil { didMove(to: view!) }
    }

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 {
            lastUpdate = currentTime
            return
        }
        let dt = currentTime - lastUpdate
        lastUpdate = currentTime

        // Scroll lane markers
        let dy = -speedY * CGFloat(dt)
        enumerateChildNodes(withName: "dash") { node, _ in
            node.position.y += dy
            if node.position.y < -40 {
                node.position.y = self.size.height + 40
            }
        }

        // Input → lateral movement
        let dx: CGFloat = 220
        var moveX: CGFloat = 0

        switch side {
        case .left:
            // Player 1 (bottom) – normal mapping
            if input?.p1Left  == true { moveX -= dx }
            if input?.p1Right == true { moveX += dx }

        case .right:
            // Player 2 (top) – MIRRORED mapping (because they face the other player)
            // Their "Left" should move to THEIR left, which is screen-right from Player 1's perspective.
            if input?.p2Left  == true { moveX += dx }   // <-- inverted
            if input?.p2Right == true { moveX -= dx }   // <-- inverted
        }
        let minX = size.width/2 - laneWidth/2
        let maxX = size.width/2 + laneWidth/2
        let newX = max(minX, min(maxX, carNode.position.x + moveX * CGFloat(dt)))
        carNode.position.x = newX
    }
}
