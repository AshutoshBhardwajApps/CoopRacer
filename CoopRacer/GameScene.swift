import SpriteKit

final class GameScene: SKScene {
    enum Side { case left, right }

    private let side: Side
    private weak var input: PlayerInput?
    private weak var coordinator: GameCoordinator?

    // Composed car
    private let carNode = SKNode()
    private var laneWidth: CGFloat { size.width * 0.40 }
    private var speedY: CGFloat = 240
    private var lastUpdate: TimeInterval = 0

    // Obstacles
    private var spawnAccumulator: TimeInterval = 0
    private var spawnInterval: TimeInterval = 1.5  // easy cadence
    private var obstacles: [SKNode] = []

    // MARK: - Init
    init(size: CGSize, side: Side, input: PlayerInput, coordinator: GameCoordinator) {
        self.side = side
        self.input = input
        self.coordinator = coordinator
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Scene setup
    override func didMove(to view: SKView) {
        removeAllChildren()
        carNode.removeAllChildren()
        obstacles.removeAll()
        addChild(carNode)

        let accent: SKColor = (side == .left) ? Theme.p1SK : Theme.p2SK

        // Track rails (leave margins so nothing sits under control bars visually)
        let inner = SKShapeNode(rectOf: CGSize(width: size.width * 0.70, height: size.height * 0.90),
                                cornerRadius: 8)
        inner.strokeColor = accent
        inner.lineWidth = 2
        inner.alpha = 0.7
        inner.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(inner)

        buildCarShape(accent: accent)

        // Car near each player's end (mirrored)
        let startY: CGFloat = (side == .left) ? size.height * 0.25 : size.height * 0.75
        carNode.position = CGPoint(x: size.width/2, y: startY)

        // Lane markers
        for i in 0..<14 { addLaneDash(y: CGFloat(i) * 70.0) }

        lastUpdate = 0
        spawnAccumulator = 0
    }

    private func buildCarShape(accent: SKColor) {
        // Body
        let body = SKShapeNode(rectOf: CGSize(width: 26, height: 44), cornerRadius: 9)
        body.fillColor = accent
        body.strokeColor = .clear
        body.zPosition = 1

        // Wheels
        func wheel(offsetX: CGFloat, offsetY: CGFloat) -> SKShapeNode {
            let w = SKShapeNode(rectOf: CGSize(width: 6, height: 12), cornerRadius: 3)
            w.fillColor = .black.withAlphaComponent(0.85)
            w.strokeColor = .clear
            w.position = CGPoint(x: offsetX, y: offsetY)
            w.zPosition = 2
            return w
        }
        let wheels = [
            wheel(offsetX: -10, offsetY: 12), wheel(offsetX: 10, offsetY: 12),
            wheel(offsetX: -10, offsetY: -12), wheel(offsetX: 10, offsetY: -12)
        ]

        // Windshield
        let wsPath = CGPath(roundedRect: CGRect(x: -9, y: 8, width: 18, height: 10),
                            cornerWidth: 3, cornerHeight: 3, transform: nil)
        let windshield = SKShapeNode(path: wsPath)
        windshield.fillColor = .white.withAlphaComponent(0.85)
        windshield.strokeColor = .clear
        windshield.zPosition = 3

        carNode.addChild(body); wheels.forEach { carNode.addChild($0) }; carNode.addChild(windshield)
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

    // MARK: - Obstacles
    private func spawnObstacle() {
        // Choose an easy, readable obstacle
        let types = ["cone", "box", "tumbleweed", "squirrel"]
        let t = types.randomElement()!

        let node: SKNode
        switch t {
        case "cone":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -8, y: -12))
            path.addLine(to: CGPoint(x: 8, y: -12))
            path.addLine(to: CGPoint(x: 0, y: 12))
            path.closeSubpath()
            let cone = SKShapeNode(path: path)
            cone.fillColor = .orange
            cone.strokeColor = .white.withAlphaComponent(0.6)
            node = cone
        case "box":
            let box = SKShapeNode(rectOf: CGSize(width: 18, height: 18), cornerRadius: 3)
            box.fillColor = SKColor(red: 0.75, green: 0.55, blue: 0.30, alpha: 1.0)
            box.strokeColor = .clear
            node = box
        case "tumbleweed":
            let weed = SKShapeNode(circleOfRadius: 10)
            weed.fillColor = SKColor(red: 0.65, green: 0.50, blue: 0.30, alpha: 1.0)
            weed.strokeColor = .white.withAlphaComponent(0.2)
            node = weed
        default: // "squirrel"
            let label = SKLabelNode(text: "🐿️")
            label.fontSize = 22
            node = label
        }

        node.name = "obstacle"
        node.zPosition = 5
        node.userData = ["touched": false] 
        // Spawn off-screen, moving toward the player
        let laneHalf = laneWidth * 0.45
        let x = CGFloat.random(in: size.width/2 - laneHalf ... size.width/2 + laneHalf)

        if side == .left {
            node.position = CGPoint(x: x, y: size.height + 30)
        } else {
            node.position = CGPoint(x: x, y: -30)
        }

        addChild(node)
        obstacles.append(node)
    }

    // MARK: - Resize
    override func didChangeSize(_ oldSize: CGSize) {
        if view != nil { didMove(to: view!) }
    }

    // MARK: - Update Loop
    override func update(_ currentTime: TimeInterval) {
        guard coordinator?.roundActive == true else { return }

        if lastUpdate == 0 { lastUpdate = currentTime; return }
        let dt = currentTime - lastUpdate
        lastUpdate = currentTime

        // Scroll lane markers
        let dir: CGFloat = (side == .left) ? -1.0 : +1.0
        let dy = dir * speedY * CGFloat(dt)

        enumerateChildNodes(withName: "dash") { node, _ in
            node.position.y += dy
            if self.side == .left {
                if node.position.y < -40 { node.position.y = self.size.height + 40 }
            } else {
                if node.position.y > self.size.height + 40 { node.position.y = -40 }
            }
        }

        // Spawn obstacles
        spawnAccumulator += dt
        if spawnAccumulator >= spawnInterval {
            spawnAccumulator = 0
            spawnInterval = Double.random(in: 1.2...1.8)
            spawnObstacle()
        }

        // Move obstacles, check “passed” & award score
        // Move obstacles, check “passed” & award score
        var toRemove: [SKNode] = []
        for ob in obstacles {
            ob.position.y += dy

            // Track touched state
            var wasTouched = (ob.userData?["touched"] as? Bool) ?? false

            // Collision detection
            let dx = abs(ob.position.x - carNode.position.x)
            let dyC = abs(ob.position.y - carNode.position.y)
            if dx < 16 && dyC < 22 {
                if !wasTouched {
                    ob.userData?["touched"] = true
                    // Flash car when bumping
                    let flash = SKAction.sequence([
                        .fadeAlpha(to: 0.4, duration: 0.05),
                        .fadeAlpha(to: 1.0, duration: 0.10)
                    ])
                    carNode.run(flash)
                }
                wasTouched = true
            }

            // If obstacle goes past player’s end
            if side == .left, ob.position.y < -40 {
                if !wasTouched { coordinator?.addScore(player1: true, points: 1) }
                toRemove.append(ob)
            } else if side == .right, ob.position.y > size.height + 40 {
                if !wasTouched { coordinator?.addScore(player1: false, points: 1) }
                toRemove.append(ob)
            }
        }
        for n in toRemove {
            n.removeFromParent()
            obstacles.removeAll { $0 == n }
        }
        for n in toRemove {
            n.removeFromParent()
            obstacles.removeAll { $0 == n }
        }

        // Inputs → lateral movement
        let vx: CGFloat = 220
        var moveX: CGFloat = 0
        switch side {
        case .left:
            if input?.p1Left  == true { moveX -= vx }
            if input?.p1Right == true { moveX += vx }
        case .right:
            // Mirrored for the top player
            if input?.p2Left  == true { moveX += vx }
            if input?.p2Right == true { moveX -= vx }
        }

        let minX = size.width/2 - laneWidth/2
        let maxX = size.width/2 + laneWidth/2
        carNode.position.x = max(minX, min(maxX, carNode.position.x + moveX * CGFloat(dt)))
    }
}
