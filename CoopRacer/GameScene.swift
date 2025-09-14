import SpriteKit

final class GameScene: SKScene {
    enum Side { case left, right }

    // Injected
    private let side: Side
    private weak var input: PlayerInput?
    private weak var coordinator: GameCoordinator?

    // Visual
    private let roadNode = SKShapeNode()
    private let carNode = SKNode()
    private var dashNodes: [SKShapeNode] = []
    private var finishLine: SKShapeNode!
    private var startLine: SKShapeNode!

    // Distance bar
    private let progressBG = SKShapeNode()
    private let progressFill = SKShapeNode()

    // Layout
    private var laneWidth: CGFloat { playableRect.width * 0.40 }
    private var playableRect: CGRect = .zero

    // Motion
    private var baseSpeed: CGFloat = 240
    private var speedMultiplier: CGFloat = 1
    private var lastUpdate: TimeInterval = 0

    // Obstacles
    private var spawnAccum: TimeInterval = 0
    private var spawnInterval: TimeInterval = 1.5
    private var obstacles: [SKNode] = []

    // Distance bookkeeping
    private var totalTrackDistance: CGFloat = 0
    private var distanceAdvanced: CGFloat = 0   // increases with world scroll amount

    // Audio
    private var engineNode: SKAudioNode?

    // Init
    init(size: CGSize, side: Side, input: PlayerInput, coordinator: GameCoordinator) {
        self.side = side
        self.input = input
        self.coordinator = coordinator
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        removeAllChildren()
        dashNodes.removeAll()
        obstacles.removeAll()
        carNode.removeAllChildren()

        // Keep road clear of control bars visually
        let marginTowardBottom: CGFloat = (side == .left) ? 90 : 10
        let marginTowardTop: CGFloat    = (side == .right) ? 90 : 10
        playableRect = CGRect(
            x: size.width * 0.15,
            y: marginTowardBottom,
            width: size.width * 0.70,
            height: size.height - marginTowardBottom - marginTowardTop
        )

        // Road (grey so wheels pop)
        roadNode.path = CGPath(roundedRect: playableRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        roadNode.fillColor = SKColor(white: 0.18, alpha: 1.0)
        roadNode.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        roadNode.lineWidth = 2
        addChild(roadNode)

        // Center dashed line
        addDashes(count: 16, spacing: 80, dashLen: 40)

        // Start / Finish
        addCheckeredLines()

        // Car
        buildCar()
        let carY: CGFloat = (side == .left) ? playableRect.minY + playableRect.height * 0.18
                                            : playableRect.maxY - playableRect.height * 0.18
        carNode.position = CGPoint(x: playableRect.midX, y: carY)
        if side == .right { carNode.zRotation = .pi }   // face the top player
        addChild(carNode)

        // Distance bar
        addProgressBar()

        // Distance sync (30s clean run reaches finish at t=0)
        let totalSeconds: CGFloat = 30
        totalTrackDistance = baseSpeed * totalSeconds
        distanceAdvanced = 0

        // Position finish far enough away to meet at t=0 if no penalties
        if side == .left {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + totalTrackDistance)
        } else {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - totalTrackDistance)
        }

        // Audio
        startEngineLoop()

        // Reset timing
        lastUpdate = 0
        spawnAccum = 0
        speedMultiplier = 1
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if view != nil { didMove(to: view!) }
    }

    // MARK: - Builders
    private func addDashes(count: Int, spacing: CGFloat, dashLen: CGFloat) {
        for i in 0..<count {
            let y = (side == .left)
                ? playableRect.minY + CGFloat(i) * spacing
                : playableRect.maxY - CGFloat(i) * spacing - dashLen

            let path = CGMutablePath()
            path.move(to: CGPoint(x: playableRect.midX, y: y))
            path.addLine(to: CGPoint(x: playableRect.midX, y: y + (side == .left ? dashLen : -dashLen)))
            let dash = SKShapeNode(path: path)
            dash.strokeColor = .white
            dash.lineWidth = 2
            dash.name = "dash"
            addChild(dash)
            dashNodes.append(dash)
        }
    }

    private func checkered(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 2)
        node.fillColor = .clear
        node.strokeColor = .clear
        let cols = 12
        let rows = 4
        let tileW = width / CGFloat(cols)
        let tileH = height / CGFloat(rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let tile = SKShapeNode(rectOf: CGSize(width: tileW - 1, height: tileH - 1))
                tile.fillColor = ((r + c) % 2 == 0) ? .white : .black
                tile.strokeColor = .clear
                tile.position = CGPoint(x: -width/2 + tileW * (CGFloat(c) + 0.5),
                                        y: -height/2 + tileH * (CGFloat(r) + 0.5))
                node.addChild(tile)
            }
        }
        node.zPosition = 30   // bump higher to ensure visibility over everything on the road
        return node
    }

    private func addCheckeredLines() {
        startLine = checkered(width: playableRect.width * 0.8, height: 18)
        finishLine = checkered(width: playableRect.width * 0.8, height: 18)

        startLine.position = CGPoint(
            x: playableRect.midX,
            y: (side == .left) ? (playableRect.minY + 20) : (playableRect.maxY - 20)
        )
        addChild(startLine)
        addChild(finishLine)
    }

    private func buildCar() {
        let accent: SKColor = (side == .left) ? Theme.p1SK : Theme.p2SK

        // Body
        let body = SKShapeNode(rectOf: CGSize(width: 26, height: 44), cornerRadius: 9)
        body.fillColor = accent
        body.strokeColor = .clear
        body.zPosition = 3

        // Wheels (dark so they pop on grey)
        func wheel(offsetX: CGFloat, offsetY: CGFloat) -> SKShapeNode {
            let w = SKShapeNode(rectOf: CGSize(width: 6, height: 12), cornerRadius: 3)
            w.fillColor = SKColor(white: 0.05, alpha: 1.0)
            w.strokeColor = .clear
            w.position = CGPoint(x: offsetX, y: offsetY)
            w.zPosition = 4
            return w
        }
        let wheels = [
            wheel(offsetX: -10, offsetY: 12), wheel(offsetX: 10, offsetY: 12),
            wheel(offsetX: -10, offsetY: -12), wheel(offsetX: 10, offsetY: -12)
        ]

        // Windshield (forward)
        let wsRect = CGRect(x: -9, y: 8, width: 18, height: 10)
        let wsPath = CGPath(roundedRect: wsRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        let windshield = SKShapeNode(path: wsPath)
        windshield.fillColor = .white.withAlphaComponent(0.85)
        windshield.strokeColor = .clear
        windshield.zPosition = 5

        carNode.addChild(body); wheels.forEach { carNode.addChild($0) }; carNode.addChild(windshield)
    }

    private func addProgressBar() {
        // A slim vertical bar near the outer edge of the road.
        // Player 1 fills upward from the bottom; Player 2 fills downward from the top.
        let barWidth: CGFloat = 8
        let barHeight: CGFloat = playableRect.height * 0.9
        let xOffset: CGFloat = playableRect.maxX + 14  // just outside the road on the right side
        let baseY = playableRect.minY + (playableRect.height - barHeight) / 2

        let bgRect = CGRect(x: xOffset - barWidth/2, y: baseY, width: barWidth, height: barHeight)
        progressBG.path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        progressBG.fillColor = SKColor(white: 1.0, alpha: 0.08)
        progressBG.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        progressBG.lineWidth = 1
        progressBG.zPosition = 30
        addChild(progressBG)

        // Start with minimal fill
        updateProgressFill(ratio: 0.0)
        addChild(progressFill)
    }

    private func updateProgressFill(ratio: CGFloat) {
        let clamped = max(0, min(1, ratio))
        let barWidth: CGFloat = 8
        let totalH: CGFloat = playableRect.height * 0.9
        let filledH = totalH * clamped

        let xOffset: CGFloat = playableRect.maxX + 14
        let baseY = playableRect.minY + (playableRect.height - totalH) / 2

        let y: CGFloat
        if side == .left {
            // Fill from bottom up
            y = baseY
        } else {
            // Fill from top down (mirror)
            y = baseY + (totalH - filledH)
        }

        let fillRect = CGRect(x: xOffset - barWidth/2, y: y, width: barWidth, height: filledH)
        progressFill.path = CGPath(roundedRect: fillRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        progressFill.fillColor = (side == .left) ? Theme.p1SK : Theme.p2SK
        progressFill.strokeColor = .clear
        progressFill.zPosition = 31
    }

    // MARK: - Obstacles
    private func spawnObstacle() {
        enum O { case cone, box, tumbleweed, squirrel }
        let t: O = [.cone, .box, .tumbleweed, .squirrel].randomElement()!

        let node: SKNode
        switch t {
        case .cone:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -8, y: -12)); p.addLine(to: CGPoint(x: 8, y: -12)); p.addLine(to: CGPoint(x: 0, y: 12)); p.closeSubpath()
            let cone = SKShapeNode(path: p)
            cone.fillColor = .orange; cone.strokeColor = .white.withAlphaComponent(0.6)
            node = cone
        case .box:
            let box = SKShapeNode(rectOf: CGSize(width: 18, height: 18), cornerRadius: 3)
            box.fillColor = SKColor(red: 0.75, green: 0.55, blue: 0.30, alpha: 1.0)
            box.strokeColor = .clear
            node = box
        case .tumbleweed:
            let weed = SKShapeNode(circleOfRadius: 10)
            weed.fillColor = SKColor(red: 0.65, green: 0.50, blue: 0.30, alpha: 1.0)
            weed.strokeColor = .white.withAlphaComponent(0.2)
            node = weed
        case .squirrel:
            let label = SKLabelNode(text: "🐿️")
            label.fontSize = 22
            node = label
        }

        node.name = "obstacle"
        node.zPosition = 10
        node.userData = ["touched": false]

        // Spawn at far side, inside lane
        let laneHalf = laneWidth * 0.45
        let x = CGFloat.random(in: playableRect.midX - laneHalf ... playableRect.midX + laneHalf)
        if side == .left {
            node.position = CGPoint(x: x, y: playableRect.maxY + 30)
        } else {
            node.position = CGPoint(x: x, y: playableRect.minY - 30)
        }

        addChild(node)
        obstacles.append(node)
    }

    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        guard coordinator?.roundActive == true else { return }
        if lastUpdate == 0 { lastUpdate = currentTime; return }
        let dt = currentTime - lastUpdate
        lastUpdate = currentTime

        // Scroll direction (toward each player)
        let dir: CGFloat = (side == .left) ? -1.0 : +1.0
        let speed = baseSpeed * speedMultiplier
        let dy = dir * speed * CGFloat(dt)

        // Advance distance for progress bar
        distanceAdvanced += abs(dy)
        let ratio = min(distanceAdvanced / totalTrackDistance, 1.0)
        updateProgressFill(ratio: ratio)

        // Wrap dashes robustly (no vanish), regardless of large dt
        let spacing: CGFloat = 80
        let dashLen: CGFloat = 40
        let totalStride = spacing * CGFloat(dashNodes.count)

        for dash in dashNodes {
            dash.position.y += dy

            if side == .left {
                // Desired domain: [minY - dashLen, minY - dashLen + totalStride)
                while dash.position.y < playableRect.minY - dashLen {
                    dash.position.y += totalStride
                }
                while dash.position.y >= playableRect.minY - dashLen + totalStride {
                    dash.position.y -= totalStride
                }
            } else {
                // Desired domain: (maxY + dashLen - totalStride, maxY + dashLen]
                while dash.position.y > playableRect.maxY + dashLen {
                    dash.position.y -= totalStride
                }
                while dash.position.y <= playableRect.maxY + dashLen - totalStride {
                    dash.position.y += totalStride
                }
            }
        }

        // Move finish line with the world
        finishLine.position.y += dy

        // Spawn/move obstacles; score only clean dodges
        spawnAccum += dt
        if spawnAccum >= spawnInterval {
            spawnAccum = 0
            spawnInterval = Double.random(in: 1.2...1.8)
            spawnObstacle()
        }

        var toRemove: [SKNode] = []
        for ob in obstacles {
            ob.position.y += dy

            // Collision (mark touched, apply smooth penalty, play sound)
            let dx = abs(ob.position.x - carNode.position.x)
            let dyC = abs(ob.position.y - carNode.position.y)
            var touched = (ob.userData?["touched"] as? Bool) ?? false
            if dx < 16 && dyC < 22 {
                if !touched {
                    ob.userData?["touched"] = true
                    touched = true
                    // flash
                    let flash = SKAction.sequence([.fadeAlpha(to: 0.4, duration: 0.05),
                                                   .fadeAlpha(to: 1.0, duration: 0.15)])
                    carNode.run(flash)
                    // slowdown + recover
                    applySmoothPenalty()
                    // crash sound
                    playCrash()
                }
            }

            // Off-screen → remove; award only if untouched
            if side == .left, ob.position.y < playableRect.minY - 40 {
                if !touched { coordinator?.addScore(player1: true, points: 1) }
                toRemove.append(ob)
            } else if side == .right, ob.position.y > playableRect.maxY + 40 {
                if !touched { coordinator?.addScore(player1: false, points: 1) }
                toRemove.append(ob)
            }
        }
        toRemove.forEach { n in n.removeFromParent() }
        obstacles.removeAll { toRemove.contains($0) }

        // Inputs → lateral movement (top player mirrored)
        let vx: CGFloat = 220
        var moveX: CGFloat = 0
        switch side {
        case .left:
            if input?.p1Left  == true { moveX -= vx }
            if input?.p1Right == true { moveX += vx }
        case .right:
            if input?.p2Left  == true { moveX += vx }   // mirrored
            if input?.p2Right == true { moveX -= vx }
        }

        let minX = playableRect.midX - laneWidth/2
        let maxX = playableRect.midX + laneWidth/2
        carNode.position.x = max(minX, min(maxX, carNode.position.x + moveX * CGFloat(dt)))
    }

    // MARK: - Penalty easing
    private func applySmoothPenalty() {
        let minMul: CGFloat = 0.6
        let end: CGFloat = 1.0
        let dur: CGFloat = 0.5

        speedMultiplier = min(speedMultiplier, minMul)

        let steps = 30
        let stepDur = dur / CGFloat(steps)
        var i = 0
        let action = SKAction.repeat(SKAction.sequence([
            SKAction.run { [weak self] in
                guard let self else { return }
                i += 1
                let t = min(1.0, CGFloat(i) / CGFloat(steps))
                let eased = 1 - pow(1 - t, 2) // easeOutQuad
                self.speedMultiplier = minMul + (end - minMul) * eased
            },
            SKAction.wait(forDuration: stepDur)
        ]), count: steps)
        run(action, withKey: "recover")
    }

    // MARK: - Sounds
    private func startEngineLoop() {
        let name = (side == .left) ? "engine_loop_p1" : "engine_loop_p2"
        if Bundle.main.url(forResource: name, withExtension: "mp3") != nil {
            let engine = SKAudioNode(fileNamed: "\(name).mp3")
            engine.autoplayLooped = true
            engine.isPositional = false
            engine.run(.changeVolume(to: 0.45, duration: 0))
            addChild(engine)
            engineNode = engine
        }
    }

    private func playCrash() {
        if Bundle.main.url(forResource: "crash", withExtension: "wav") != nil {
            run(.playSoundFileNamed("crash.wav", waitForCompletion: false))
        }
    }
}
