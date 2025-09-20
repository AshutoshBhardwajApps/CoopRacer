import SpriteKit
import QuartzCore   // CACurrentMediaTime()

final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Public API
    enum Side { case left, right }

    private let side: Side
    private unowned let input: PlayerInput
    private unowned let coordinator: GameCoordinator

    // MARK: - Nodes
    private var roadNode = SKNode()
    private var roadRect: CGRect = .zero
    private var centerDashContainer = SKNode()
    private var startChecker: SKSpriteNode!

    private(set) var car: SKSpriteNode!

    // MARK: - Gameplay state
    private var laneWidth: CGFloat = 0
    private var speedBase: CGFloat = 280.0
    private var strafeSpeed: CGFloat = 280.0
    private var slowdownUntil: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0

    private var spawnAccumulator: TimeInterval = 0
    private var spawnInterval: TimeInterval = 1.2

    private var passedSet = Set<SKNode>()
    private var touchedSet = Set<SKNode>()

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

    // MARK: - Scene life cycle
    override func didMove(to view: SKView) {
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        buildRoad()
        buildCar()            // box cars (old look/size)
        buildStartChecker()   // place relative to car

        // Clear old state
        passedSet.removeAll()
        touchedSet.removeAll()
        obstaclesNode().removeAllChildren()
    }

    // MARK: - Builders
    private func buildRoad() {
        roadNode.removeFromParent()
        roadNode = SKNode()
        addChild(roadNode)

        // Road bounds: use scene size explicitly (avoid any 'bounds' helpers)
        let insetX: CGFloat = 10
        roadRect = CGRect(origin: .zero, size: size).insetBy(dx: insetX, dy: 0)
        laneWidth = roadRect.width

        // Road background
        let roadBG = SKShapeNode(rect: roadRect, cornerRadius: 12)
        roadBG.fillColor = SKColor(white: 0.18, alpha: 1) // grey so cars pop
        roadBG.strokeColor = SKColor(white: 1, alpha: 0.08)
        roadBG.lineWidth = 2
        roadBG.zPosition = 0
        roadNode.addChild(roadBG)

        // Center dashed line (scrolling)
        centerDashContainer.removeAllChildren()
        centerDashContainer.zPosition = 20
        roadNode.addChild(centerDashContainer)

        let dashHeight: CGFloat = 32
        let dashWidth: CGFloat = 6
        let gap: CGFloat = 40
        let total = Int(ceil(size.height / (dashHeight + gap))) + 3

        for i in 0..<total {
            let dash = SKShapeNode(rectOf: CGSize(width: dashWidth, height: dashHeight), cornerRadius: 3)
            dash.fillColor = .white
            dash.strokeColor = .clear
            dash.alpha = 0.85
            dash.zPosition = 20
            dash.position = CGPoint(x: roadRect.midX, y: CGFloat(i) * (dashHeight + gap))
            centerDashContainer.addChild(dash)
        }

        // Obstacles parent
        let obstacles = SKNode()
        obstacles.name = "obstacles"
        obstacles.zPosition = 40
        roadNode.addChild(obstacles)
    }

    /// Simple colored rectangle car (box car) — same feel as before
    private func buildCar() {
        let color: SKColor = (side == .left) ? .red : .blue
        let w = laneWidth * 0.25       // ⬅️ previous footprint
        let h = laneWidth * 0.45

        car = SKSpriteNode(color: color, size: CGSize(width: w, height: h))
        car.zPosition = 100
        addChild(car)

        // Physics body
        car.physicsBody = SKPhysicsBody(rectangleOf: car.size)
        car.physicsBody?.isDynamic = true
        car.physicsBody?.affectedByGravity = false
        car.physicsBody?.allowsRotation = false
        car.physicsBody?.categoryBitMask = 0x1 << 1
        car.physicsBody?.collisionBitMask = 0
        car.physicsBody?.contactTestBitMask = 0xFFFFFFFF

        // Start fully visible inside the road (same comfortable placement)
        let marginY = h * 0.7
        if side == .left {
            car.position = CGPoint(x: roadRect.midX, y: roadRect.minY + marginY)
        } else {
            car.position = CGPoint(x: roadRect.midX, y: roadRect.maxY - marginY)
        }
    }

    // Checker (clearly visible, sized to lane)
    private func buildStartChecker() {
        let checker = SKSpriteNode(texture: makeCheckerTexture())
        checker.size.height = 26
        checker.size.width  = roadRect.width * 0.88
        checker.zPosition = 60
        startChecker = checker
        addChild(checker)
        startChecker.position = checkerAheadOfCar()
    }

    private func makeCheckerTexture() -> SKTexture {
        let height: CGFloat = 22
        let width: CGFloat = roadRect.width * 0.88
        let renderSize = CGSize(width: width, height: height)

        UIGraphicsBeginImageContextWithOptions(renderSize, false, 0)
        let ctx = UIGraphicsGetCurrentContext()!
        let square = height
        var toggle = false
        var x: CGFloat = 0
        while x < renderSize.width + square {
            let rect = CGRect(x: x, y: 0, width: square, height: square)
            (toggle ? UIColor.white : UIColor.black).setFill()
            ctx.fill(rect)
            toggle.toggle()
            x += square
        }
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }

    private func checkerAheadOfCar() -> CGPoint {
        // Keep a healthy distance so it's clearly visible
        let offset = car.size.height * 0.65
        if side == .left {
            return CGPoint(x: roadRect.midX, y: car.position.y + offset)   // ahead = +Y
        } else {
            return CGPoint(x: roadRect.midX, y: car.position.y - offset)   // ahead = -Y
        }
    }

    // MARK: - Update loop
    override func update(_ currentTime: TimeInterval) {
        // Delta time
        let dt: TimeInterval = (lastUpdateTime == 0) ? (1.0 / 60.0) : min(1.0 / 30.0, currentTime - lastUpdateTime)
        lastUpdateTime = currentTime

        // Center dashed line scroll:
        // Bottom (left) "drives up" → road moves DOWN (dashDir = -1)
        // Top (right) "drives down" → road moves UP  (dashDir = +1)
        let dashDir: CGFloat = (side == .left) ? -1.0 : +1.0
        let dashSpeed: CGFloat = coordinator.raceStarted ? 240 : 120
        let dashScroll = CGFloat(dt) * dashSpeed * dashDir

        for dash in centerDashContainer.children {
            dash.position.y += dashScroll
            if dashDir < 0 {
                if dash.position.y < -40 { dash.position.y += (size.height + 80) }
            } else {
                if dash.position.y > size.height + 40 { dash.position.y -= (size.height + 80) }
            }
        }

        // Start checker (always handled)
        let checkerSpeed: CGFloat = 560
        if coordinator.raceStarted {
            // Slide away opposite to player's forward motion:
            // left lane forward is +Y -> checker slides DOWN (-Y)
            // right lane forward is -Y -> checker slides UP (+Y)
            let dir: CGFloat = (side == .left) ? -1.0 : +1.0
            startChecker.position.y += CGFloat(dt) * checkerSpeed * dir
        } else {
            startChecker.position = checkerAheadOfCar()
        }

        // If round inactive, we’re done after animating road/checker
        guard coordinator.roundActive else { return }

        // Lateral input
        let (leftPressed, rightPressed) = currentLR()
        var dx: CGFloat = 0; if leftPressed { dx -= 1 }; if rightPressed { dx += 1 }

        // Keep car inside road
        let halfW = car.size.width * 0.5
        let minX = roadRect.minX + halfW + 6
        let maxX = roadRect.maxX - halfW - 6
        if dx != 0 {
            let slowCoef: CGFloat = isSlowed(now: currentTime) ? 0.35 : 1.0
            let step = dx * strafeSpeed * CGFloat(dt) * slowCoef
            car.position.x = min(max(car.position.x + step, minX), maxX)
        }

        // Forward illusion — move obstacles in the same direction as the road drift
        let obsDir: CGFloat = dashDir
        if coordinator.raceStarted {
            let speedCoef: CGFloat = isSlowed(now: currentTime) ? 0.45 : 1.0
            let dy = obsDir * speedBase * speedCoef * CGFloat(dt)
            obstaclesNode().children.forEach { $0.position.y += dy }
        }

        // Spawning & scoring
        spawnAccumulator += dt
        if coordinator.raceStarted && spawnAccumulator >= spawnInterval {
            spawnAccumulator = 0
            spawnObstacle()
        }
        processScoring()
        cullOffscreenObstacles()
    }

    // MARK: - Input
    private func currentLR() -> (Bool, Bool) {
        switch side {
        case .left:  return (input.p1Left, input.p1Right)
        case .right: return (input.p2Left, input.p2Right)
        }
    }

    // MARK: - Obstacles
    private func obstaclesNode() -> SKNode {
        if let n = roadNode.childNode(withName: "obstacles") { return n }
        let n = SKNode()
        n.name = "obstacles"
        n.zPosition = 40
        roadNode.addChild(n)
        return n
    }

    private func spawnObstacle() {
        // Smaller obstacle (back to earlier feel)
        let w = laneWidth * 0.14
        let h = laneWidth * 0.14

        let node = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 6)
        node.fillColor = .orange
        node.strokeColor = .clear
        node.zPosition = 40
        node.name = "obstacle"
        node.userData = ["touched": false]

        // Horizontal range inside lane
        let half = laneWidth * 0.5
        let minX = roadRect.midX - half + w * 0.5 + 6
        let maxX = roadRect.midX + half - w * 0.5 - 6
        let x = CGFloat.random(in: minX...maxX)

        // Spawn from far edge in movement direction (to drift across the lane)
        let buffer: CGFloat = 50
        let y: CGFloat = (side == .left) ? (roadRect.maxY + buffer) : (roadRect.minY - buffer)

        node.position = CGPoint(x: x, y: y)

        // (Optional) physics for contact hooks
        node.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = 0x1 << 3
        node.physicsBody?.collisionBitMask = 0
        node.physicsBody?.contactTestBitMask = 0xFFFFFFFF

        obstaclesNode().addChild(node)
    }

    private func cullOffscreenObstacles() {
        let buf: CGFloat = 80
        let minY = roadRect.minY - buf
        let maxY = roadRect.maxY + buf
        obstaclesNode().children.forEach { n in
            if n.position.y < minY || n.position.y > maxY {
                n.removeFromParent()
            }
        }
    }

    private func processScoring() {
        // Score when an untouched obstacle passes the car
        for n in obstaclesNode().children {
            if touchedSet.contains(n) || passedSet.contains(n) { continue }

            let passed: Bool
            if side == .left {
                // road drifts down; obstacle "passes" when it's below the car
                passed = n.position.y < car.position.y - car.size.height * 0.30
            } else {
                // road drifts up; obstacle "passes" when it's above the car
                passed = n.position.y > car.position.y + car.size.height * 0.30
            }

            if passed {
                let wasTouched = (n.userData?["touched"] as? Bool) ?? false
                if !wasTouched {
                    if side == .left { coordinator.p1Score += 1 } else { coordinator.p2Score += 1 }
                }
                passedSet.insert(n)
            }
        }
    }

    // MARK: - Physics (slowdown on crash)
    func didBegin(_ contact: SKPhysicsContact) {
        var other: SKNode?
        if contact.bodyA.node === car { other = contact.bodyB.node }
        else if contact.bodyB.node === car { other = contact.bodyA.node }
        guard let obstacle = other else { return }

        // Mark touched so no score later
        if obstacle.userData == nil { obstacle.userData = [:] }
        obstacle.userData?["touched"] = true
        touchedSet.insert(obstacle)

        slowdownUntil = max(slowdownUntil, CACurrentMediaTime() + 3.0)
        flash(node: car)
    }

    private func isSlowed(now: TimeInterval) -> Bool { now < slowdownUntil }

    private func flash(node: SKNode) {
        let fadeOut = SKAction.fadeAlpha(to: 0.4, duration: 0.06)
        let fadeIn  = SKAction.fadeAlpha(to: 1.0, duration: 0.06)
        node.run(.repeat(.sequence([fadeOut, fadeIn]), count: 5))
    }

    // MARK: - Hooks (kept for compatibility)
    func onRaceStarted() { /* box cars: no engine audio */ }
    func onRaceEnded()   { /* box cars: no engine audio */ }
}
