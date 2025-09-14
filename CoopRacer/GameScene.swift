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
    private var startLine: SKShapeNode!
    private var finishLine: SKShapeNode!

    // Distance/progress bar
    private let progressBG = SKShapeNode()
    private let progressFill = SKShapeNode()

    // Center dashed line (phase-driven so it never disappears)
    private var dashNodes: [SKShapeNode] = []
    private var dashPhase: CGFloat = 0
    private let dashCount: Int = 26
    private let dashSpacing: CGFloat = 64
    private let dashLen: CGFloat = 36

    // Layout
    private var playableRect: CGRect = .zero
    private var laneWidth: CGFloat { playableRect.width * 0.40 }

    // Full-width movement (tiny edge pad so wheels don’t clip)
    private var carEdgePad: CGFloat { 15 }   // tweak 12–16 to taste
    private var roadMinX: CGFloat { playableRect.minX + carEdgePad }
    private var roadMaxX: CGFloat { playableRect.maxX - carEdgePad }

    // Motion
    private var baseSpeed: CGFloat = 280       // a touch faster so slowdowns feel obvious
    private var speedMultiplier: CGFloat = 1   // eased after bumps
    private var lastUpdate: TimeInterval = 0

    // Obstacles
    private var spawnAccum: TimeInterval = 0
    private var spawnInterval: TimeInterval = 1.5
    private var obstacles: [SKNode] = []

    // Distance bookkeeping (finish sync + progress bar)
    private var totalTrackDistance: CGFloat = 0
    private var distanceAdvanced: CGFloat = 0

    // Slowdown feedback
    private var isRecovering = false
    private var slowVignette: SKShapeNode?

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
        carNode.removeAllChildren()
        dashNodes.removeAll()
        obstacles.removeAll()

        // Keep road away from control bars (solid black bars live outside)
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
        roadNode.zPosition = 5
        addChild(roadNode)

        // Center dashed line (phase-driven, *never* flickers)
        buildDashes()

        // Start / Finish (high z so always visible)
        buildCheckeredLines()

        // Car (simple top-down)
        buildCar()
        let carY: CGFloat = (side == .left)
            ? playableRect.minY + playableRect.height * 0.18
            : playableRect.maxY - playableRect.height * 0.18
        carNode.position = CGPoint(x: playableRect.midX, y: carY)
        if side == .right { carNode.zRotation = .pi } // face the top player
        addChild(carNode)

        // Place START just in front of the car (toward driving direction)
        if side == .left {
            startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - 28) // toward bottom
        } else {
            startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + 28) // toward top
        }

        // Distance bar
        addProgressBar()
        updateProgressFill(ratio: 0)

        // Finish distance: clean 30s run hits finish exactly at t=0
        let totalSeconds: CGFloat = 30
        totalTrackDistance = baseSpeed * totalSeconds
        distanceAdvanced = 0
        if side == .left {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + totalTrackDistance)
        } else {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - totalTrackDistance)
        }

        // Audio (optional files)
        startEngineLoop()

        // Vignette overlay (over gameplay rect)
        ensureSlowVignette()

        // Reset
        lastUpdate = 0
        spawnAccum = 0
        speedMultiplier = 1
        dashPhase = 0
        layoutDashes() // initial placement
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if view != nil { didMove(to: view!) }
    }

    // MARK: - Builders
    private func buildDashes() {
        for _ in 0..<dashCount {
            let path = CGMutablePath()
            path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: dashLen))
            let dash = SKShapeNode(path: path)
            dash.strokeColor = .white
            dash.lineWidth = 2
            dash.zPosition = 15 // above road, below checkers
            addChild(dash)
            dashNodes.append(dash)
        }
    }

    private func layoutDashes() {
        for (i, dash) in dashNodes.enumerated() {
            let baseOffset = CGFloat(i) * dashSpacing + dashPhase
            let yStart: CGFloat
            let yEnd: CGFloat
            if side == .left {
                yStart = playableRect.minY + baseOffset - dashLen
                yEnd   = yStart + dashLen
            } else {
                yStart = playableRect.maxY - baseOffset + dashLen
                yEnd   = yStart - dashLen
            }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: playableRect.midX, y: yStart))
            path.addLine(to: CGPoint(x: playableRect.midX, y: yEnd))
            dash.path = path
        }
    }

    private func checkered(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 2)
        node.fillColor = .clear
        node.strokeColor = .clear
        let cols = 12, rows = 4
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
        node.zPosition = 100
        return node
    }

    private func buildCheckeredLines() {
        startLine = checkered(width: playableRect.width * 0.8, height: 18)
        finishLine = checkered(width: playableRect.width * 0.8, height: 18)
        addChild(startLine)
        addChild(finishLine)
    }

    private func buildCar() {
        let accent: SKColor = (side == .left) ? Theme.p1SK : Theme.p2SK

        // Body
        let body = SKShapeNode(rectOf: CGSize(width: 26, height: 44), cornerRadius: 9)
        body.fillColor = accent
        body.strokeColor = .clear
        body.zPosition = 30

        // Wheels (dark so they pop on grey)
        func wheel(_ x: CGFloat, _ y: CGFloat) -> SKShapeNode {
            let w = SKShapeNode(rectOf: CGSize(width: 6, height: 12), cornerRadius: 3)
            w.fillColor = SKColor(white: 0.05, alpha: 1.0)
            w.strokeColor = .clear
            w.position = CGPoint(x: x, y: y)
            w.zPosition = 31
            return w
        }
        let wheels = [wheel(-10, 12), wheel(10, 12), wheel(-10, -12), wheel(10, -12)]

        // Windshield (forward)
        let wsRect = CGRect(x: -9, y: 8, width: 18, height: 10)
        let wsPath = CGPath(roundedRect: wsRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        let windshield = SKShapeNode(path: wsPath)
        windshield.fillColor = .white.withAlphaComponent(0.85)
        windshield.strokeColor = .clear
        windshield.zPosition = 32

        carNode.addChild(body); wheels.forEach { carNode.addChild($0) }; carNode.addChild(windshield)
    }

    private func addProgressBar() {
        let barWidth: CGFloat = 8
        let barHeight: CGFloat = playableRect.height * 0.9
        let xOffset: CGFloat = playableRect.maxX + 14
        let baseY = playableRect.minY + (playableRect.height - barHeight) / 2

        let bgRect = CGRect(x: xOffset - barWidth/2, y: baseY, width: barWidth, height: barHeight)
        progressBG.path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        progressBG.fillColor = SKColor(white: 1.0, alpha: 0.08)
        progressBG.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        progressBG.lineWidth = 1
        progressBG.zPosition = 60
        addChild(progressBG)

        progressFill.zPosition = 61
        addChild(progressFill)
    }

    private func updateProgressFill(ratio: CGFloat) {
        let clamped = max(0, min(1, ratio))
        let barWidth: CGFloat = 8
        let totalH: CGFloat = playableRect.height * 0.9
        let filledH = totalH * clamped

        let xOffset: CGFloat = playableRect.maxX + 14
        let baseY = playableRect.minY + (playableRect.height - totalH) / 2

        let y: CGFloat = (side == .left) ? baseY : baseY + (totalH - filledH)
        let fillRect = CGRect(x: xOffset - barWidth/2, y: y, width: barWidth, height: filledH)
        progressFill.path = CGPath(roundedRect: fillRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        progressFill.fillColor = (side == .left) ? Theme.p1SK : Theme.p2SK
        progressFill.strokeColor = .clear
    }

    // MARK: - Vignette helper
    private func ensureSlowVignette() {
        guard slowVignette == nil else { return }
        // Cover only the gameplay rect so control bars stay clean
        let v = SKShapeNode(rect: playableRect)
        v.position = .zero
        v.fillColor = .red
        v.strokeColor = .clear
        v.alpha = 0.0
        v.zPosition = 2000
        v.isUserInteractionEnabled = false
        addChild(v)
        slowVignette = v
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
        node.zPosition = 40
        node.userData = ["touched": false]

        // Spawn anywhere across the full road width
        let x = CGFloat.random(in: roadMinX ... roadMaxX)
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
        if lastUpdate == 0 { lastUpdate = currentTime; return }
        let dt = currentTime - lastUpdate
        lastUpdate = currentTime

        // Lateral steering always allowed (pre-aim during countdown)
        applyLateralMovement(dt: dt)

        // If race hasn't started, do not move world elements
        guard coordinator?.raceStarted == true else { return }

        // If round is over, ensure engine fades/stops and bail early
        if coordinator?.roundActive == false {
            stopEngineLoop()
            return
        }

        // Scrolling toward each player
        let dir: CGFloat = (side == .left) ? -1.0 : +1.0
        let speed = baseSpeed * speedMultiplier
        let dy = dir * speed * CGFloat(dt)

        // Advance distance & progress bar
        distanceAdvanced += abs(dy)
        let ratio = min(distanceAdvanced / totalTrackDistance, 1.0)
        updateProgressFill(ratio: ratio)

        // Center dashed line via PHASE (bulletproof)
        dashPhase = (dashPhase + abs(dy)).truncatingRemainder(dividingBy: dashSpacing)
        layoutDashes()

        // Move checkered lines with the world
        startLine.position.y += dy
        finishLine.position.y += dy

        // Remove start line after it scrolls off the player's edge
        if side == .left, startLine.position.y < playableRect.minY - 40 {
            startLine.removeFromParent()
        } else if side == .right, startLine.position.y > playableRect.maxY + 40 {
            startLine.removeFromParent()
        }

        // Spawn / move obstacles; score clean dodges only
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
                    let flash = SKAction.sequence([.fadeAlpha(to: 0.4, duration: 0.05),
                                                   .fadeAlpha(to: 1.0, duration: 0.15)])
                    carNode.run(flash)
                    applySmoothPenalty()
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
    }

    private func applyLateralMovement(dt: TimeInterval) {
        let vx: CGFloat = 220
        var moveX: CGFloat = 0
        switch side {
        case .left:
            if input?.p1Left  == true { moveX -= vx }
            if input?.p1Right == true { moveX += vx }
        case .right:
            // mirrored for top player
            if input?.p2Left  == true { moveX += vx }
            if input?.p2Right == true { moveX -= vx }
        }
        // Clamp across the full road width
        carNode.position.x = max(roadMinX, min(roadMaxX, carNode.position.x + moveX * CGFloat(dt)))
    }

    // MARK: - Penalty easing (3s, strong)
    private func applySmoothPenalty() {
        // Instantly drop to ~35% speed, then ease back to 1.0 over 3s.
        // Also show a soft red vignette + desaturate the car + duck engine volume.
        let minMul: CGFloat = 0.35
        let end: CGFloat = 1.0
        let dur: CGFloat = 3.0

        isRecovering = true
        speedMultiplier = min(speedMultiplier, minMul)

        // Vignette flash up, then hold faintly during recovery
        slowVignette?.removeAllActions()
        slowVignette?.run(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.08),
            .fadeAlpha(to: 0.18, duration: 0.20)
        ]))

        // Desaturate car (tint gray)
        carNode.removeAction(forKey: "recoverTint")
        let tintDown = SKAction.colorize(with: .gray, colorBlendFactor: 0.7, duration: 0.12)
        tintDown.timingMode = .easeOut
        carNode.run(tintDown, withKey: "recoverTint")

        // Duck engine
        engineNode?.run(.changeVolume(to: 0.15, duration: 0.10))

        // Smooth ease back to normal over 3.0s
        removeAction(forKey: "recover")
        let steps = 180
        let stepDur = dur / CGFloat(steps)
        var i = 0
        let action = SKAction.repeat(SKAction.sequence([
            SKAction.run { [weak self] in
                guard let self else { return }
                i += 1
                let t = min(1.0, CGFloat(i) / CGFloat(steps))
                // easeOutQuad
                let eased = 1 - pow(1 - t, 2)
                self.speedMultiplier = minMul + (end - minMul) * eased
            },
            SKAction.wait(forDuration: stepDur)
        ]), count: steps)

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.isRecovering = false
            // Restore visuals and audio
            let tintUp = SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.20)
            tintUp.timingMode = .easeIn
            self.carNode.run(tintUp, withKey: "recoverTint")
            self.slowVignette?.run(.fadeAlpha(to: 0.0, duration: 0.25))
            self.engineNode?.run(.changeVolume(to: 0.45, duration: 0.25))
        }

        run(.sequence([action, finish]), withKey: "recover")
    }

    // MARK: - Sounds
    private func startEngineLoop() {
        // Optional: add engine_loop_p1.mp3 / engine_loop_p2.mp3 (or .wav) to your bundle
        let name = (side == .left) ? "engine_loop_p1" : "engine_loop_p2"
        if Bundle.main.url(forResource: name, withExtension: "mp3") != nil {
            let engine = SKAudioNode(fileNamed: "\(name).mp3")
            engine.autoplayLooped = true
            engine.isPositional = false
            engine.run(.changeVolume(to: 0.45, duration: 0))
            addChild(engine)
            engineNode = engine
        } else if Bundle.main.url(forResource: name, withExtension: "wav") != nil {
            let engine = SKAudioNode(fileNamed: "\(name).wav")
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
        } else if Bundle.main.url(forResource: "crash", withExtension: "mp3") != nil {
            run(.playSoundFileNamed("crash.mp3", waitForCompletion: false))
        }
    }

    private func stopEngineLoop() {
        guard let engine = engineNode else { return }
        engine.run(.sequence([
            .changeVolume(to: 0.0, duration: 0.5),  // smooth fade out
            .removeFromParent()
        ]))
        engineNode = nil
    }
}
