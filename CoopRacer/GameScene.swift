import SpriteKit

final class GameScene: SKScene {
    enum Side { case left, right }

    // Which mode this scene is running in
    enum Mode {
        case solo      // single lane (SoloGameView)
        case versus    // 2-player races (ContentView)
    }

    // === Car appearance toggle ===
    private let chosenCarPNG: String
    private let USE_IMAGE_CAR = true
    private let LEFT_CAR_IMAGE  = "Audi"
    private let RIGHT_CAR_IMAGE = "Audi"
    private let usePNGCar = true

    // Match the old box-car footprint exactly (30×50 points)
    private let CAR_BASE_SIZE = CGSize(width: 30, height: 50)
    private let CAR_SCALE: CGFloat = 1.0

    // Injected
    private let side: Side
    private weak var input: PlayerInput?
    private weak var coordinator: GameCoordinator?

    // Mode (solo or versus)
    private let mode: Mode

    // Difficulty (pulled from SettingsStore at init time)
    private let difficulty: SpeedLevel

    // Visual
    private var roadNode = SKShapeNode()
    private var carNode = SKNode()
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
    private var carEdgePad: CGFloat { 15 }
    private var roadMinX: CGFloat { playableRect.minX + carEdgePad }
    private var roadMaxX: CGFloat { playableRect.maxX - carEdgePad }

    // Remember original spawn Y so restarts go back to true start
    private var initialCarY: CGFloat = 0

    // Motion
    private var baseSpeed: CGFloat = 280       // base, will be tuned by difficulty
    private var speedMultiplier: CGFloat = 1   // eased after bumps
    private var lastUpdate: TimeInterval = 0
    private var elapsedRaceTime: TimeInterval = 0   // tracks how long this race has been running

    // Obstacles
    private var spawnAccum: TimeInterval = 0
    private var spawnInterval: TimeInterval = 1.5
    private var obstacles: [SKNode] = []

    // Identify obstacle type for animations
    private enum ObstacleKind {
        case cone
        case box
        case tumbleweed
        case squirrel
        case pothole
        case rock
        case oilSlick
        case slowTruck
    }

    // Distance bookkeeping (finish sync + progress bar)
    private var totalTrackDistance: CGFloat = 0
    private var distanceAdvanced: CGFloat = 0

    // Whether this lane has already told the coordinator it reached finish
    private var hasSignalledFinish: Bool = false

    // Slowdown feedback
    private var isRecovering = false
    private var slowVignette: SKShapeNode?

    // Pause tracking (so we only fade once)
    private var wasPaused: Bool = false

    // Audio
    private var engineNode: SKAudioNode?
    private var engineStarted: Bool = false

    // === SOLO-ONLY FOREST STRIPS ===
    private var treeNodes: [SKNode] = []
    private let treeOffsetX: CGFloat = 26              // how far from road edge
    private let treeVerticalSpacingRange: ClosedRange<CGFloat> = 44...64

    // MARK: - Init

    init(size: CGSize,
         side: Side,
         input: PlayerInput,
         coordinator: GameCoordinator,
         carPNG: String,
         mode: Mode = .versus)  // default keeps 2-player unchanged
    {
        self.side = side
        self.input = input
        self.coordinator = coordinator
        self.chosenCarPNG = carPNG
        self.difficulty = SettingsStore.shared.selectedSpeedLevel
        self.mode = mode

        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        removeAllChildren()
        carNode.removeAllChildren()
        dashNodes.removeAll()
        obstacles.removeAll()
        treeNodes.forEach { $0.removeFromParent() }
        treeNodes.removeAll()

        // Keep road away from control bars
        let marginTowardBottom: CGFloat = (side == .left) ? 90 : 10
        let marginTowardTop: CGFloat    = (side == .right) ? 90 : 10

        // Default (versus) road size
        var roadX      = size.width * 0.15
        var roadWidth  = size.width * 0.70
        let roadHeight = size.height - marginTowardBottom - marginTowardTop

        // 🔥 SOLO MODE: make the road narrower so it feels closer to a 2-player lane
        if mode == .solo {
            let inset: CGFloat = size.width * 0.25   // 25% from each side → 50% width total
            roadX     = inset
            roadWidth = size.width - inset * 2
        }

        playableRect = CGRect(
            x: roadX,
            y: marginTowardBottom,
            width: roadWidth,
            height: roadHeight
        )

        // Difficulty
        configureBaseSpeed()

        // Road
        roadNode = SKShapeNode(rect: playableRect, cornerRadius: 10)
        roadNode.fillColor = SKColor(white: 0.18, alpha: 1.0)
        roadNode.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        roadNode.lineWidth = 2
        roadNode.zPosition = 5
        addChild(roadNode)

        // Dashes
        buildDashes()
        layoutDashes()

        // Start / Finish
        buildCheckeredLines()

        // Car
        let accent: SKColor = (side == .left) ? (Theme.p1SK ?? .red) : (Theme.p2SK ?? .blue)
        if usePNGCar {
            let carName = (side == .left)
                ? SettingsStore.shared.player1Car
                : SettingsStore.shared.player2Car
            carNode = makePNGCar(textureName: carName)
        } else {
            carNode = makeCar(color: accent)
        }

        let carY: CGFloat = (side == .left)
            ? playableRect.minY + playableRect.height * 0.18
            : playableRect.maxY - playableRect.height * 0.18

        carNode.position = CGPoint(x: playableRect.midX, y: carY)
        initialCarY = carY

        if side == .right { carNode.zRotation = .pi }
        carNode.zPosition = 100
        addChild(carNode)

        // Start line just behind car (in driving direction)
        let behindOffset: CGFloat = 28
        if side == .left {
            startLine.position = CGPoint(x: playableRect.midX,
                                         y: carNode.position.y - behindOffset)
        } else {
            startLine.position = CGPoint(x: playableRect.midX,
                                         y: carNode.position.y + behindOffset)
        }

        // Progress bar
        addProgressBar()
        updateProgressFill(ratio: 0)

        // Finish distance: 30s clean run
        let totalSeconds: CGFloat = 30
        totalTrackDistance = baseSpeed * totalSeconds
        distanceAdvanced = 0
        hasSignalledFinish = false

        if side == .left {
            finishLine.position = CGPoint(x: playableRect.midX,
                                          y: carNode.position.y + totalTrackDistance)
        } else {
            finishLine.position = CGPoint(x: playableRect.midX,
                                          y: carNode.position.y - totalTrackDistance)
        }

        engineStarted = false
        ensureSlowVignette()

        // 🌲 Seed dense forest strips – SOLO ONLY
        setupForestIfSolo()

        lastUpdate = 0
        spawnAccum = 0
        speedMultiplier = 1
        dashPhase = 0
        elapsedRaceTime = 0
        wasPaused = false
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if view != nil { didMove(to: view!) }
    }

    // MARK: - Difficulty setup

    private func configureBaseSpeed() {
        let base: CGFloat
        switch difficulty {
        case .easy:   base = 260
        case .medium: base = 300
        case .hard:   base = 340
        case .insane: base = 380
        }

        // 🔥 SOLO MODE: slightly faster overall to compensate for more vertical view
        let modeMultiplier: CGFloat = (mode == .solo) ? 1.12 : 1.0
        baseSpeed = base * modeMultiplier
    }

    // MARK: - Car builder

    private func makeCar(color: SKColor) -> SKNode {
        let targetW = CAR_BASE_SIZE.width  * CAR_SCALE
        let targetH = CAR_BASE_SIZE.height * CAR_SCALE

        if USE_IMAGE_CAR {
            let name = (side == .left) ? LEFT_CAR_IMAGE : RIGHT_CAR_IMAGE
            let tex  = SKTexture(imageNamed: name)
            tex.filteringMode = .linear

            let ar = tex.size().width / tex.size().height
            var finalW = targetW
            var finalH = targetH
            if ar > (targetW / targetH) {
                finalH = finalW / ar
            } else {
                finalW = finalH * ar
            }

            let sprite = SKSpriteNode(texture: tex, size: CGSize(width: finalW, height: finalH))
            sprite.zPosition = 100
            sprite.colorBlendFactor = 0.0
            return sprite
        } else {
            let car = SKNode()

            let targetW = CAR_BASE_SIZE.width  * CAR_SCALE
            let targetH = CAR_BASE_SIZE.height * CAR_SCALE
            let body = SKShapeNode(rectOf: CGSize(width: targetW, height: targetH), cornerRadius: 6)
            body.fillColor = color
            body.strokeColor = .black
            body.lineWidth = 1.5
            body.zPosition = 30
            car.addChild(body)

            let wheelW: CGFloat = 8 * CAR_SCALE
            let wheelH: CGFloat = 14 * CAR_SCALE
            let wheelSize = CGSize(width: wheelW, height: wheelH)
            let xOff: CGFloat = (targetW / 2) - (wheelW / 2) - 2
            let yOff: CGFloat = (targetH / 2) - (wheelH / 2) - 2
            let wheelOffsets: [(CGFloat, CGFloat)] = [(-xOff, -yOff), (xOff, -yOff), (-xOff, yOff), (xOff, yOff)]
            for (dx, dy) in wheelOffsets {
                let wheel = SKShapeNode(rectOf: wheelSize, cornerRadius: 2 * CAR_SCALE)
                wheel.fillColor = SKColor(white: 0.08, alpha: 1.0)
                wheel.strokeColor = .black
                wheel.lineWidth = 1
                wheel.position = CGPoint(x: dx, y: dy)
                wheel.zPosition = 31
                car.addChild(wheel)
            }

            let windshield = SKShapeNode(rectOf: CGSize(width: 20*CAR_SCALE, height: 10*CAR_SCALE),
                                         cornerRadius: 2*CAR_SCALE)
            windshield.fillColor = SKColor(cgColor: CGColor(red: 0.75, green: 0.9, blue: 1.0, alpha: 0.9))
            windshield.strokeColor = .clear
            windshield.position = CGPoint(x: 0, y: (targetH/2) - (10*CAR_SCALE))
            windshield.zPosition = 32
            car.addChild(windshield)

            func tail(_ x: CGFloat) -> SKShapeNode {
                let r: CGFloat = 2.5 * CAR_SCALE
                let t = SKShapeNode(circleOfRadius: r)
                t.fillColor = .red
                t.strokeColor = .clear
                t.position = CGPoint(x: x, y: -(targetH/2) + r*1.5)
                t.zPosition = 32
                return t
            }
            car.addChild(tail(-(targetW/2) + 8*CAR_SCALE))
            car.addChild(tail( (targetW/2) - 8*CAR_SCALE))

            car.zPosition = 100
            return car
        }
    }

    // MARK: - Builders

    private func buildDashes() {
        dashNodes.forEach { $0.removeFromParent() }
        dashNodes.removeAll()

        for _ in 0..<dashCount {
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: dashLen))
            let dash = SKShapeNode(path: path)
            dash.strokeColor = .white
            dash.lineWidth = 2
            dash.zPosition = 15
            addChild(dash)
            dashNodes.append(dash)
        }
    }

    private func layoutDashes() {
        for (i, dash) in dashNodes.enumerated() {
            let base = CGFloat(i) * dashSpacing
            let p = CGMutablePath()

            if side == .left {
                let yStart = playableRect.minY + base - dashPhase
                let yEnd   = yStart + dashLen
                p.move(to: CGPoint(x: playableRect.midX, y: yStart))
                p.addLine(to: CGPoint(x: playableRect.midX, y: yEnd))
            } else {
                let yStart = playableRect.maxY - base + dashPhase
                let yEnd   = yStart - dashLen
                p.move(to: CGPoint(x: playableRect.midX, y: yStart))
                p.addLine(to: CGPoint(x: playableRect.midX, y: yEnd))
            }

            dash.path = p
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
                tile.position = CGPoint(
                    x: -width/2 + tileW * (CGFloat(c) + 0.5),
                    y: -height/2 + tileH * (CGFloat(r) + 0.5)
                )
                node.addChild(tile)
            }
        }
        node.zPosition = 100
        return node
    }

    // MARK: - Forest canopy builder (top-down trees)

    private func makeTreeCanopy(baseRadius: CGFloat = 18) -> SKNode {
        let node = SKNode()
        node.zPosition = 3   // below road (road is 5), so it feels in the ground plane

        // Palette: slightly different greens + one more “dusty” color
        let palettes: [[SKColor]] = [
            [
                SKColor(red: 0.10, green: 0.40, blue: 0.15, alpha: 1.0),
                SKColor(red: 0.16, green: 0.55, blue: 0.22, alpha: 1.0),
                SKColor(red: 0.06, green: 0.30, blue: 0.11, alpha: 1.0)
            ],
            [
                SKColor(red: 0.08, green: 0.33, blue: 0.18, alpha: 1.0),
                SKColor(red: 0.14, green: 0.50, blue: 0.25, alpha: 1.0),
                SKColor(red: 0.03, green: 0.22, blue: 0.10, alpha: 1.0)
            ],
            [
                SKColor(red: 0.23, green: 0.48, blue: 0.24, alpha: 1.0),
                SKColor(red: 0.33, green: 0.60, blue: 0.30, alpha: 1.0),
                SKColor(red: 0.18, green: 0.36, blue: 0.18, alpha: 1.0)
            ]
        ]

        let colors = palettes.randomElement() ?? palettes[0]

        // 3–5 overlapping “blobs” to make a bushy canopy
        let blobCount = Int.random(in: 3...5)
        for _ in 0..<blobCount {
            let rScale = CGFloat.random(in: 0.7...1.2)
            let radius = baseRadius * rScale

            let offsetRadius = baseRadius * CGFloat.random(in: 0.0...0.6)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dx = cos(angle) * offsetRadius
            let dy = sin(angle) * offsetRadius

            let circle = SKShapeNode(circleOfRadius: radius)
            circle.fillColor = colors.randomElement() ?? colors[0]
            circle.strokeColor = SKColor(white: 0.08, alpha: 0.8)
            circle.lineWidth = 1.0
            circle.position = CGPoint(x: dx, y: dy)
            circle.zPosition = CGFloat.random(in: 0...1.0)  // tiny variation
            circle.alpha = CGFloat.random(in: 0.90...1.0)

            node.addChild(circle)
        }

        // Slight overall rotation so trees don’t look copy-pasted
        node.zRotation = CGFloat.random(in: -(.pi/16)...(.pi/16))

        // OPTIONAL: tiny trunk hint (barely visible under canopy)
        if Bool.random() {
            let trunk = SKShapeNode(rectOf: CGSize(width: baseRadius * 0.35,
                                                   height: baseRadius * 0.6),
                                    cornerRadius: baseRadius * 0.12)
            trunk.fillColor = SKColor(red: 0.45, green: 0.28, blue: 0.14, alpha: 1.0)
            trunk.strokeColor = .clear
            trunk.position = CGPoint(x: 0, y: -baseRadius * 0.9)
            trunk.zPosition = -1
            trunk.alpha = 0.85
            node.addChild(trunk)
        }

        // 🐿 Occasionally add a little static squirrel perched on top
        if Double.random(in: 0...1) < 0.20 {
            let squirrel = SKLabelNode(text: "🐿️")
            squirrel.fontSize = baseRadius * 1.1
            squirrel.verticalAlignmentMode = .center
            squirrel.zPosition = 10
            squirrel.position = CGPoint(x: CGFloat.random(in: -4...4),
                                        y: baseRadius * 1.1)

            // Tiny idle wiggle so it feels alive but not distracting
            let tilt = SKAction.sequence([
                SKAction.rotate(byAngle: .pi/64, duration: 0.25),
                SKAction.rotate(byAngle: -(.pi/64), duration: 0.25)
            ])
            tilt.timingMode = .easeInEaseOut

            let pause = SKAction.wait(forDuration: Double.random(in: 1.5...3.0))
            squirrel.run(.repeatForever(.sequence([pause, tilt])))

            node.addChild(squirrel)
        }

        return node
    }

    private func buildCheckeredLines() {
        startLine = checkered(width: playableRect.width * 0.8, height: 18)
        finishLine = checkered(width: playableRect.width * 0.8, height: 18)
        startLine.zPosition = 60
        finishLine.zPosition = 60
        addChild(startLine)
        addChild(finishLine)
    }

    private func makePNGCar(textureName: String, tint: SKColor? = nil) -> SKSpriteNode {
        let tex = SKTexture(imageNamed: textureName)
        tex.filteringMode = .linear

        let targetWidth = laneWidth * 0.8
        let aspect = tex.size().height / tex.size().width
        let targetSize = CGSize(width: targetWidth, height: targetWidth * aspect)

        let node = SKSpriteNode(texture: tex, size: targetSize)
        node.zPosition = 100

        if let tint = tint {
            node.color = tint
            node.colorBlendFactor = 0.85
        } else {
            node.colorBlendFactor = 0.0
        }
        return node
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
        progressFill.fillColor = (side == .left) ? (Theme.p1SK ?? .red) : (Theme.p2SK ?? .blue)
        progressFill.strokeColor = .clear
    }

    // MARK: - SOLO FOREST HELPERS

    private func setupForestIfSolo() {
        guard mode == .solo else { return }

        treeNodes.forEach { $0.removeFromParent() }
        treeNodes.removeAll()

        // Seed trees from just below to well above the play area
        let startY = playableRect.minY - 80
        let endY   = playableRect.maxY + 160
        var y = startY
        while y < endY {
            spawnTreeRow(atY: y)
            y += CGFloat.random(in: treeVerticalSpacingRange)
        }
    }

    private func spawnTreeRow(atY y: CGFloat) {
        guard mode == .solo else { return }

        let leftX  = playableRect.minX - treeOffsetX
        let rightX = playableRect.maxX + treeOffsetX

        // Left tree
        let leftTree = makeTreeNode()
        leftTree.position = CGPoint(
            x: leftX + CGFloat.random(in: -10...6),
            y: y    + CGFloat.random(in: -6...6)
        )
        leftTree.zPosition = 3
        addChild(leftTree)
        treeNodes.append(leftTree)

        // Right tree
        let rightTree = makeTreeNode()
        rightTree.position = CGPoint(
            x: rightX + CGFloat.random(in: -6...10),
            y: y     + CGFloat.random(in: -6...6)
        )
        rightTree.zPosition = 3
        addChild(rightTree)
        treeNodes.append(rightTree)
    }

    private func makeTreeNode() -> SKNode {
        let node = SKNode()

        // MARK: - Trunk
        let trunkHeight: CGFloat = CGFloat.random(in: 12...20)
        let trunkWidth: CGFloat  = CGFloat.random(in: 3.0...4.5)

        let trunk = SKShapeNode(rectOf: CGSize(width: trunkWidth, height: trunkHeight),
                                cornerRadius: 1.5)
        trunk.fillColor   = SKColor(red: 0.40, green: 0.25, blue: 0.12, alpha: 1.0)
        trunk.strokeColor = SKColor(white: 0.0, alpha: 0.35)
        trunk.lineWidth   = 1
        trunk.position    = CGPoint(x: 0, y: trunkHeight * 0.3)
        trunk.zPosition   = 1
        node.addChild(trunk)

        // MARK: - Canopy “style”
        // A few different palettes: deep forest, bright, dry/brownish
        let greenPalette: [[SKColor]] = [
            // Deep forest
            [
                SKColor(red: 0.10, green: 0.40, blue: 0.16, alpha: 1.0),
                SKColor(red: 0.16, green: 0.50, blue: 0.18, alpha: 1.0),
                SKColor(red: 0.07, green: 0.33, blue: 0.13, alpha: 1.0)
            ],
            // Bright mixed greens
            [
                SKColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1.0),
                SKColor(red: 0.24, green: 0.62, blue: 0.30, alpha: 1.0),
                SKColor(red: 0.33, green: 0.70, blue: 0.32, alpha: 1.0)
            ],
            // Slightly dry / autumn hint
            [
                SKColor(red: 0.42, green: 0.45, blue: 0.16, alpha: 1.0),
                SKColor(red: 0.46, green: 0.38, blue: 0.18, alpha: 1.0),
                SKColor(red: 0.50, green: 0.32, blue: 0.14, alpha: 1.0)
            ]
        ]

        let palette = greenPalette.randomElement() ?? [SKColor.green]
        let mainRadius: CGFloat = CGFloat.random(in: 13...22)

        // MARK: - Multi-blob canopy
        let blobCount = Int.random(in: 3...5)

        for i in 0..<blobCount {
            let rScale: CGFloat
            switch i {
            case 0:
                rScale = 1.0
            case 1:
                rScale = CGFloat.random(in: 0.7...0.9)
            default:
                rScale = CGFloat.random(in: 0.5...0.8)
            }

            let radius = mainRadius * rScale

            // Offset blobs so canopy looks uneven
            let offsetX = CGFloat.random(in: -radius * 0.5 ... radius * 0.5)
            let offsetY = CGFloat.random(in: radius * 0.1  ... radius * 0.8)

            let blob = SKShapeNode(circleOfRadius: radius)
            blob.fillColor   = palette.randomElement() ?? .green
            blob.strokeColor = SKColor(white: 0.0, alpha: 0.35)
            blob.lineWidth   = 1

            blob.position = CGPoint(
                x: offsetX,
                y: trunkHeight * 0.6 + offsetY
            )
            blob.zPosition = 2 + CGFloat(i) * 0.01
            node.addChild(blob)

            // Optional subtle highlight on largest blob
            if i == 0 && Bool.random() {
                let highlight = SKShapeNode(circleOfRadius: radius * 0.55)
                highlight.fillColor = SKColor(white: 1.0, alpha: 0.10)
                highlight.strokeColor = .clear
                highlight.position = CGPoint(x: blob.position.x - radius * 0.25,
                                             y: blob.position.y + radius * 0.15)
                highlight.zPosition = blob.zPosition + 0.02
                node.addChild(highlight)
            }
        }

        // MARK: - Occasional static squirrel in tree 🐿
        if Bool.random() && Bool.random() { // ~25% of trees get one
            let squirrel = SKLabelNode(text: "🐿️")
            squirrel.fontSize = CGFloat.random(in: 10...13)
            squirrel.verticalAlignmentMode = .center
            squirrel.horizontalAlignmentMode = .center

            // Perch somewhere near the top of the canopy
            let perchRadius = mainRadius * 0.6
            let angle = CGFloat.random(in: -.pi/4 ... .pi/4)  // slightly left/right
            let perchX = cos(angle) * perchRadius
            let perchY = trunkHeight * 0.8 + mainRadius + CGFloat.random(in: -4...4)

            squirrel.position = CGPoint(x: perchX, y: perchY)
            squirrel.zPosition = 4
            node.addChild(squirrel)
        }

        return node
    }

    private func updateForest(withWorldDeltaY dy: CGFloat) {
        guard mode == .solo else { return }

        // Move trees with the world (same dy as road / obstacles)
        for t in treeNodes {
            t.position.y += dy
        }

        // Remove trees that are far below the visible area
        let removeY = playableRect.minY - 140
        treeNodes.removeAll { node in
            if node.position.y < removeY {
                node.removeFromParent()
                return true
            }
            return false
        }

        // Ensure we always have trees extending above the visible region
        let highestY = treeNodes.map(\.position.y).max() ?? (playableRect.minY - 80)
        if highestY < playableRect.maxY + 140 {
            let newY = highestY + CGFloat.random(in: treeVerticalSpacingRange)
            spawnTreeRow(atY: newY)
        }
    }

    // MARK: - New round reset

    func prepareForNewRound() {
        obstacles.forEach { $0.removeFromParent() }
        obstacles.removeAll()

        treeNodes.forEach { $0.removeFromParent() }
        treeNodes.removeAll()

        lastUpdate = 0
        spawnAccum = 0
        speedMultiplier = 1
        dashPhase = 0
        elapsedRaceTime = 0
        distanceAdvanced = 0
        hasSignalledFinish = false
        isRecovering = false

        carNode.removeAllActions()
        carNode.position = CGPoint(x: playableRect.midX, y: initialCarY)
        carNode.zRotation = (side == .right) ? .pi : 0

        updateProgressFill(ratio: 0)
        layoutDashes()

        let behind: CGFloat = 28
        if startLine == nil {
            startLine = checkered(width: playableRect.width * 0.8, height: 18)
            startLine.zPosition = 60
            addChild(startLine)
        } else if startLine.parent == nil {
            addChild(startLine)
        }

        if side == .left {
            startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - behind)
        } else {
            startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + behind)
        }

        if finishLine != nil {
            finishLine.removeFromParent()
        }
        finishLine = checkered(width: playableRect.width * 0.8, height: 18)
        finishLine.zPosition = 60
        addChild(finishLine)

        let totalSeconds: CGFloat = 30
        totalTrackDistance = baseSpeed * totalSeconds
        if side == .left {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + totalTrackDistance)
        } else {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - totalTrackDistance)
        }

        slowVignette?.removeAllActions()
        slowVignette?.alpha = 0.0

        engineNode?.run(.changeVolume(to: 0.45, duration: 0.0))
        engineStarted = false
        stopEngineLoop()

        // Re-seed forest for a fresh run in solo mode
        setupForestIfSolo()
    }

    // MARK: - Vignette helper

    private func ensureSlowVignette() {
        guard slowVignette == nil else { return }
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
        // Pick pool by difficulty
        let pool: [ObstacleKind]
        switch difficulty {
        case .easy:
            pool = [.cone, .box, .tumbleweed, .squirrel]
        case .medium:
            pool = [.cone, .box, .tumbleweed, .squirrel, .pothole, .rock]
        case .hard:
            pool = [.cone, .box, .tumbleweed, .squirrel, .pothole, .rock, .oilSlick]
        case .insane:
            pool = [.cone, .box, .tumbleweed, .squirrel, .pothole, .rock, .oilSlick, .slowTruck]
        }

        let kind = pool.randomElement()!
        let node: SKNode

        switch kind {
        case .cone:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -8, y: -12))
            p.addLine(to: CGPoint(x:  8, y: -12))
            p.addLine(to: CGPoint(x:  0, y:  12))
            p.closeSubpath()
            let cone = SKShapeNode(path: p)
            cone.fillColor = .orange
            cone.strokeColor = .white.withAlphaComponent(0.6)
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
            label.verticalAlignmentMode = .center
            node = label

        case .pothole:
            let hole = SKShapeNode(circleOfRadius: 11)
            hole.fillColor = SKColor(white: 0.05, alpha: 1.0)
            hole.strokeColor = SKColor(white: 0.6, alpha: 0.5)
            hole.lineWidth = 1.5
            node = hole

        case .rock:
            let rock = SKShapeNode(circleOfRadius: 9)
            rock.fillColor = SKColor(white: 0.55, alpha: 1.0)
            rock.strokeColor = SKColor(white: 0.2, alpha: 0.7)
            rock.lineWidth = 1.2
            node = rock

        case .oilSlick:
            let slickSize = CGSize(width: 32, height: 14)
            let slick = SKShapeNode(rectOf: slickSize, cornerRadius: 6)
            slick.fillColor = SKColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1.0)
            slick.strokeColor = SKColor(white: 1.0, alpha: 0.15)
            slick.lineWidth = 1
            node = slick

        case .slowTruck:
            let truckSize = CGSize(width: 26, height: 30)
            let truck = SKShapeNode(rectOf: truckSize, cornerRadius: 4)
            truck.fillColor = SKColor(red: 0.20, green: 0.40, blue: 0.80, alpha: 1.0)
            truck.strokeColor = SKColor(white: 0.1, alpha: 0.9)
            truck.lineWidth = 1.5

            let cab = SKShapeNode(rectOf: CGSize(width: 18, height: 10), cornerRadius: 3)
            cab.fillColor = SKColor(white: 0.9, alpha: 0.9)
            cab.strokeColor = .clear
            cab.position = CGPoint(x: 0, y: truckSize.height * 0.15)
            truck.addChild(cab)

            node = truck
        }

        node.name = "obstacle"
        node.zPosition = 40
        node.userData = ["touched": false]

        let x = CGFloat.random(in: roadMinX ... roadMaxX)
        if side == .left {
            node.position = CGPoint(x: x, y: playableRect.maxY + 30)
        } else {
            node.position = CGPoint(x: x, y: playableRect.minY - 30)
        }

        addChild(node)
        obstacles.append(node)

        // SOLO-ONLY MOTION: animated tumbleweed / squirrel
        if mode == .solo {
            applySoloMotion(to: node, kind: kind)
        }
    }

    // SOLO-mode obstacle behaviours
    private func applySoloMotion(to node: SKNode, kind: ObstacleKind) {
        switch kind {
        case .tumbleweed:
            // 🌾 Drift sideways + spin as it rolls down the road
            let dir: CGFloat = Bool.random() ? 1 : -1
            let driftDistance = CGFloat.random(in: 40...80) * dir
            let driftDuration = TimeInterval.random(in: 2.0...3.5)

            let drift = SKAction.moveBy(x: driftDistance, y: 0, duration: driftDuration)
            drift.timingMode = .easeInEaseOut

            let clamp = SKAction.run { [weak self, weak node] in
                guard let self, let node = node else { return }
                var x = node.position.x
                x = max(self.roadMinX, min(self.roadMaxX, x))
                node.position.x = x
            }

            let driftLoop = SKAction.repeatForever(SKAction.sequence([drift, clamp]))
            node.run(driftLoop)

            let spinAngle = dir * .pi * 2
            let spin = SKAction.rotate(byAngle: spinAngle, duration: driftDuration)
            node.run(.repeatForever(spin))

        case .squirrel:
            // 🐿 Extra-lively squirrel:
            //  - Direction-aware hops (face == movement)
            //  - "Panic hop" if the car gets too close
            //  - Idle blink/sniff animations
            //  - Rare instant dash bursts

            guard let label = node as? SKLabelNode else { return }

            // Center vertically so hops look tidy
            label.verticalAlignmentMode = .center

            // MARK: Facing helper
            func applyFacing(dir: Int, to label: SKLabelNode) {
                // Base scale (1 if 0)
                let base = max(abs(label.xScale), 1.0)

                if dir > 0 {
                    // Moving RIGHT → face RIGHT → flip horizontally
                    label.xScale = -base
                } else {
                    // Moving LEFT → face LEFT (default)
                    label.xScale = +base
                }
            }

            // MARK: Initial direction
            let initialDir: Int = Bool.random() ? -1 : 1
            label.userData = (label.userData ?? NSMutableDictionary())
            label.userData?["dir"] = initialDir
            label.userData?["panicking"] = false

            applyFacing(dir: initialDir, to: label)

            let baseHopDuration: TimeInterval = 0.28

            // MARK: Main hop behaviour
            let hop = SKAction.run { [weak self, weak label] in
                guard let self,
                      let label = label
                else { return }

                var dir = (label.userData?["dir"] as? Int) ?? 1
                dir = (dir == 0) ? 1 : dir

                let roll = Double.random(in: 0...1)
                var dx: CGFloat
                var hopDuration = baseHopDuration

                if roll < 0.70 {
                    // 70% → hop in facing direction
                    dx = CGFloat(dir) * CGFloat.random(in: 25...45)

                } else if roll < 0.95 {
                    // 25% → small random wiggle (slightly left/right)
                    dx = CGFloat.random(in: -14...14)
                    if dx > 0 {
                        dir = 1
                    } else if dx < 0 {
                        dir = -1
                    }

                } else {
                    // 5% → instant dash burst in a direction
                    dir = Bool.random() ? 1 : -1
                    dx = CGFloat(dir) * CGFloat.random(in: 60...110)
                    hopDuration = 0.18   // faster dash
                }

                // Save updated direction + apply facing
                label.userData?["dir"] = dir
                applyFacing(dir: dir, to: label)

                // Clamp target X to road
                let targetX = max(self.roadMinX,
                                  min(self.roadMaxX, label.position.x + dx))

                // Horizontal movement
                let move = SKAction.moveTo(x: targetX, duration: hopDuration)
                move.timingMode = .easeInEaseOut

                // Little hop arc (up then down)
                let liftUp = SKAction.moveBy(x: 0, y: 4, duration: hopDuration / 2)
                liftUp.timingMode = .easeOut
                let drop = SKAction.moveBy(x: 0, y: -4, duration: hopDuration / 2)
                drop.timingMode = .easeIn

                label.run(.group([move, SKAction.sequence([liftUp, drop])]))
            }

            // Random delay between hops
            let wait = SKAction.wait(forDuration: Double.random(in: 0.25...0.55))
            let hopSequence = SKAction.sequence([wait, hop])
            label.run(.repeatForever(hopSequence), withKey: "squirrelHop")

            // MARK: Panic hop – when car gets too close
            let panicCheck = SKAction.run { [weak self, weak label] in
                guard
                    let self,
                    let label = label
                else { return }

                // Don’t spam panic if already in it
                let isPanicking = (label.userData?["panicking"] as? Bool) ?? false
                if isPanicking { return }

                // Distance to player car
                let dx = abs(label.position.x - self.carNode.position.x)
                let dy = abs(label.position.y - self.carNode.position.y)

                // If car is close enough in both axes, panic-hop
                if dx < 28 && dy < 80 {
                    label.userData?["panicking"] = true

                    // Decide direction AWAY from car
                    let dir: Int = (label.position.x < self.carNode.position.x) ? -1 : 1
                    let panicDx = CGFloat(dir) * CGFloat.random(in: 55...95)
                    let panicDuration: TimeInterval = 0.16

                    applyFacing(dir: dir, to: label)
                    label.userData?["dir"] = dir

                    let targetX = max(self.roadMinX,
                                      min(self.roadMaxX, label.position.x + panicDx))

                    let move = SKAction.moveTo(x: targetX, duration: panicDuration)
                    move.timingMode = .easeOut

                    // Higher, sharper hop when panicking
                    let liftUp = SKAction.moveBy(x: 0, y: 8, duration: panicDuration * 0.5)
                    liftUp.timingMode = .easeOut
                    let drop  = SKAction.moveBy(x: 0, y: -8, duration: panicDuration * 0.5)
                    drop.timingMode = .easeIn

                    let panicHop = SKAction.group([move, SKAction.sequence([liftUp, drop])])

                    label.run(panicHop) {
                        // Cooldown before another panic
                        label.run(.wait(forDuration: 0.7)) {
                            label.userData?["panicking"] = false
                        }
                    }
                }
            }

            let panicWait = SKAction.wait(forDuration: 0.10)
            let panicLoop = SKAction.sequence([panicWait, panicCheck])
            label.run(.repeatForever(panicLoop), withKey: "squirrelPanic")

            // MARK: Blink / twitch animation
            let blink = SKAction.run { [weak label] in
                guard let label = label else { return }

                // Quick “blink” via y-scale squish
                let squish = SKAction.scaleY(to: 0.65, duration: 0.05)
                let restore = SKAction.scaleY(to: 1.0, duration: 0.07)
                let tinyTilt = SKAction.sequence([
                    SKAction.rotate(byAngle: .pi / 32, duration: 0.04),
                    SKAction.rotate(byAngle: -.pi / 32, duration: 0.04)
                ])
                label.run(.group([SKAction.sequence([squish, restore]), tinyTilt]))
            }

            let blinkWait = SKAction.wait(forDuration: Double.random(in: 2.0...4.0))
            let blinkLoop = SKAction.sequence([blinkWait, blink])
            label.run(.repeatForever(blinkLoop), withKey: "squirrelBlink")

            // MARK: Idle “sniff” animation
            let sniff = SKAction.run { [weak label] in
                guard let label = label else { return }

                // Tiny up/down bob + micro scale change
                let up = SKAction.moveBy(x: 0, y: 2, duration: 0.08)
                up.timingMode = .easeOut
                let down = SKAction.moveBy(x: 0, y: -2, duration: 0.10)
                down.timingMode = .easeIn

                let squash = SKAction.scaleY(to: 1.08, duration: 0.08)
                let unsquash = SKAction.scaleY(to: 1.0, duration: 0.10)

                label.run(.group([
                    SKAction.sequence([up, down]),
                    SKAction.sequence([squash, unsquash])
                ]))
            }

            let sniffWait = SKAction.wait(forDuration: Double.random(in: 3.0...6.0))
            let sniffLoop = SKAction.sequence([sniffWait, sniff])
            label.run(.repeatForever(sniffLoop), withKey: "squirrelSniff")

        default:
            break
        }
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 {
            lastUpdate = currentTime
            return
        }

        // Clamp dt so we don't teleport forward after a pause / hitch
        let rawDt = currentTime - lastUpdate
        let dt = min(rawDt, 0.05)   // max 50ms frame
        lastUpdate = currentTime

        if coordinator?.isPaused == true {
            if !wasPaused {
                stopEngineLoop()
                engineStarted = false
                wasPaused = true
            }
            return
        } else if wasPaused {
            if coordinator?.raceStarted == true {
                startEngineLoop()
                engineStarted = true
            }
            wasPaused = false
        }

        applyLateralMovement(dt: dt)

        if coordinator?.raceStarted != true {
            if engineStarted {
                stopEngineLoop()
                engineStarted = false
            }

            let behind: CGFloat = 28
            if side == .left {
                startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - behind)
            } else {
                startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + behind)
            }

            updateProgressFill(ratio: 0)
            return
        }

        if hasSignalledFinish { return }

        if coordinator?.roundActive == false {
            stopEngineLoop()
            engineStarted = false
            return
        }

        if !engineStarted {
            startEngineLoop()
            engineStarted = true
        }

        elapsedRaceTime += dt

        // ----------------- STAGE-BASED TUNING (time in run) -----------------
        let stage = min(2, Int(elapsedRaceTime / 10.0))

        var stageSpeedBoost: CGFloat = 1.0
        var stageSpawnScale: Double = 1.0

        switch stage {
        case 0:
            stageSpeedBoost = 1.0
            stageSpawnScale = 1.0
        case 1:
            stageSpeedBoost = 1.15
            stageSpawnScale = 0.85
        default:
            stageSpeedBoost = 1.30
            stageSpawnScale = 0.70
        }

        // ----------------- DIFFICULTY-BASED TUNING -----------------
        let diffBoost: CGFloat
        var diffSpawnScale: Double   // NOTE: var so we can tweak for solo

        switch difficulty {
        case .easy:
            diffBoost = 1.0
            diffSpawnScale = 1.0
        case .medium:
            diffBoost = 1.10
            diffSpawnScale = 0.65
        case .hard:
            diffBoost = 1.20
            diffSpawnScale = 0.45
        case .insane:
            diffBoost = 1.30
            diffSpawnScale = 0.35
        }

        // 🔥 SOLO MODE: denser traffic on higher difficulties
        if mode == .solo {
            switch difficulty {
            case .easy:
                // keep chill
                break
            case .medium:
                diffSpawnScale *= 0.85    // ~15% more obstacles
            case .hard:
                diffSpawnScale *= 0.70    // ~30% more obstacles
            case .insane:
                diffSpawnScale *= 0.55    // ~45% more obstacles
            }
        }

        // Final spawn scale combines time-in-run & difficulty
        let combinedSpawnScale = stageSpawnScale * diffSpawnScale

        // ----------------- WORLD SCROLL SPEED -----------------
        let worldDir: CGFloat = (side == .left) ? -1.0 : +1.0
        let speed = baseSpeed * speedMultiplier * stageSpeedBoost * diffBoost
        let dy = worldDir * speed * CGFloat(dt)

        distanceAdvanced += abs(dy)
        let ratio = min(distanceAdvanced / totalTrackDistance, 1.0)
        updateProgressFill(ratio: ratio)

        if !hasSignalledFinish && ratio >= 1.0 {
            hasSignalledFinish = true

            if side == .left {
                coordinator?.markFinished(player: 1)
            } else {
                coordinator?.markFinished(player: 2)
            }

            stopEngineLoop()
            engineStarted = false
            return
        }

        dashPhase = (dashPhase + abs(dy)).truncatingRemainder(dividingBy: dashSpacing)
        layoutDashes()

        startLine.position.y += dy
        finishLine.position.y += dy

        if side == .left,
           startLine.parent != nil,
           startLine.position.y < playableRect.minY - 40 {
            startLine.removeFromParent()
        } else if side == .right,
                  startLine.parent != nil,
                  startLine.position.y > playableRect.maxY + 40 {
            startLine.removeFromParent()
        }

        // 🌲 Move / maintain forest strips for SOLO
        updateForest(withWorldDeltaY: dy)

        // Obstacles
        spawnAccum += dt
        if spawnAccum >= spawnInterval {
            spawnAccum = 0

            // Base interval depends on mode & difficulty
            let baseIntervalRange: ClosedRange<Double>

            if mode == .solo {
                // SOLO: tighter intervals on harder modes
                switch difficulty {
                case .easy:
                    baseIntervalRange = 0.9...1.4
                case .medium:
                    baseIntervalRange = 0.7...1.1
                case .hard:
                    baseIntervalRange = 0.55...0.95
                case .insane:
                    baseIntervalRange = 0.45...0.85
                }
            } else {
                // Versus: keep old behaviour
                baseIntervalRange = 0.9...1.4
            }

            let baseInterval = Double.random(in: baseIntervalRange)
            spawnInterval = baseInterval * combinedSpawnScale

            spawnObstacle()
        }

        var toRemove: [SKNode] = []
        for ob in obstacles {
            ob.position.y += dy

            let dx = abs(ob.position.x - carNode.position.x)
            let dyC = abs(ob.position.y - carNode.position.y)
            var touched = (ob.userData?["touched"] as? Bool) ?? false
            if dx < 16 && dyC < 22 {
                if !touched {
                    ob.userData?["touched"] = true
                    touched = true
                    let flash = SKAction.sequence([
                        .fadeAlpha(to: 0.4, duration: 0.05),
                        .fadeAlpha(to: 1.0, duration: 0.15)
                    ])
                    carNode.run(flash)
                    applySmoothPenalty()
                    playCrash()
                }
            }

            var scored = (ob.userData?["scored"] as? Bool) ?? false
            if !touched && !scored {
                if side == .left {
                    if ob.position.y <= (carNode.position.y - 12) {
                        coordinator?.addScore(player1: true, points: 1)
                        ob.userData?["scored"] = true
                        scored = true
                    }
                } else {
                    if ob.position.y >= (carNode.position.y + 12) {
                        coordinator?.addScore(player1: false, points: 1)
                        ob.userData?["scored"] = true
                        scored = true
                    }
                }
            }

            if side == .left, ob.position.y < playableRect.minY - 40 {
                toRemove.append(ob)
            } else if side == .right, ob.position.y > playableRect.maxY + 40 {
                toRemove.append(ob)
            }
        }
        toRemove.forEach { $0.removeFromParent() }
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
            if input?.p2Left  == true { moveX += vx }
            if input?.p2Right == true { moveX -= vx }
        }
        carNode.position.x = max(roadMinX, min(roadMaxX, carNode.position.x + moveX * CGFloat(dt)))
    }

    // MARK: - Penalty easing

    private func applySmoothPenalty() {
        let minMul: CGFloat = 0.35
        let end: CGFloat = 1.0
        let dur: CGFloat = 3.0

        isRecovering = true
        speedMultiplier = min(speedMultiplier, minMul)

        slowVignette?.removeAllActions()
        slowVignette?.run(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.08),
            .fadeAlpha(to: 0.18, duration: 0.20)
        ]))

        if !usePNGCar {
            carNode.removeAction(forKey: "recoverTint")
            let tintDown = SKAction.colorize(with: .gray, colorBlendFactor: 0.7, duration: 0.12)
            tintDown.timingMode = .easeOut
            carNode.run(tintDown, withKey: "recoverTint")
        }

        engineNode?.run(.changeVolume(to: 0.15, duration: 0.10))

        removeAction(forKey: "recover")
        let steps = 180
        let stepDur = dur / CGFloat(steps)
        var i = 0
        let action = SKAction.repeat(SKAction.sequence([
            SKAction.run { [weak self] in
                guard let self else { return }
                i += 1
                let t = min(1.0, CGFloat(i) / CGFloat(steps))
                let eased = 1 - pow(1 - t, 2)
                self.speedMultiplier = minMul + (end - minMul) * eased
            },
            SKAction.wait(forDuration: stepDur)
        ]), count: steps)

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.isRecovering = false
            if !self.usePNGCar {
                let tintUp = SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.20)
                tintUp.timingMode = .easeIn
                self.carNode.run(tintUp, withKey: "recoverTint")
            }
            self.slowVignette?.run(.fadeAlpha(to: 0.0, duration: 0.25))
            self.engineNode?.run(.changeVolume(to: 0.45, duration: 0.25))
        }

        run(.sequence([action, finish]), withKey: "recover")
    }

    // MARK: - Sounds

    private func startEngineLoop() {
        guard SettingsStore.shared.effectsEnabled else { return }

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
        guard SettingsStore.shared.effectsEnabled else { return }

        if Bundle.main.url(forResource: "crash", withExtension: "wav") != nil {
            run(.playSoundFileNamed("crash.wav", waitForCompletion: false))
        } else if Bundle.main.url(forResource: "crash", withExtension: "mp3") != nil {
            run(.playSoundFileNamed("crash.mp3", waitForCompletion: false))
        }
    }

    private func stopEngineLoop() {
        guard let engine = engineNode else { return }
        engine.run(.sequence([
            .changeVolume(to: 0.0, duration: 0.5),
            .removeFromParent()
        ]))
        engineNode = nil
    }
}
