import SpriteKit

final class GameScene: SKScene {
    enum Side { case left, right }

    // === Car appearance toggle ===
    private let chosenCarPNG: String
    private let USE_IMAGE_CAR = true            // <- set to false to go back to drawn car
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

    // Layout mode: when true the road fills more of the screen (used in single-player)
    private let isFullWidth: Bool

    // Endless survival mode: no finish line, continuous speed escalation, 3 lives
    private let isEndlessMode: Bool

    // Difficulty (pulled from SettingsStore at init time)
    private let difficulty: SpeedLevel

    // Visual
    private var roadNode = SKShapeNode()
    private var carNode = SKNode()
    private var startLine: SKShapeNode?
    private var finishLine: SKShapeNode?

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

    private var carEdgePad: CGFloat { 15 }
    private var roadMinX: CGFloat { playableRect.minX + carEdgePad }
    private var roadMaxX: CGFloat { playableRect.maxX - carEdgePad }

    // MARK: - Angular control-point road (Road Fighter style)
    // Road is a list of (leftX, rightX, y) points sorted by ascending Y.
    // Each frame they scroll down (for P1). Old points are removed at the bottom;
    // new points are generated at the top using the angular segment generator.
    private struct RoadPoint {
        var leftX:  CGFloat
        var rightX: CGFloat
        var y:      CGFloat
    }
    private var roadPoints: [RoadPoint] = []
    private let pointSpacing: CGFloat = 130          // px between consecutive points

    // Generator state
    private var genLeft:          CGFloat = 0        // current left-edge X at generator head
    private var genRight:         CGFloat = 0        // current right-edge X at generator head
    private var genLeftDelta:     CGFloat = 0        // shift added to left edge per new point
    private var genRightDelta:    CGFloat = 0        // shift added to right edge per new point
    private var genSegsRemaining: Int     = 0        // points remaining on this behaviour

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

    // Distance bookkeeping (finish sync + progress bar)
    private var totalTrackDistance: CGFloat = 0
    private var distanceAdvanced: CGFloat = 0

    // Whether this lane has already told the coordinator it reached finish
    private var hasSignalledFinish: Bool = false

    // Slowdown feedback
    private var isRecovering = false
    private var slowVignette: SKShapeNode?

    // Nitro boost (solo-with-bots only)
    private var boostCharge: CGFloat = 0
    private let boostMax:          CGFloat = 100
    private let boostDrainRate:    CGFloat = 35    // per second; full charge lasts ~2.85 s
    private let boostFillPerDodge: CGFloat = 22    // charge per clean obstacle dodge
    private let boostSpeedMult:    CGFloat = 1.22

    // MARK: - Bot opponents (solo race only)
    private let botCount: Int
    private let botDifficulty: BotDifficulty

    private struct BotState {
        var distanceAdvanced: CGFloat = 0
        var x: CGFloat = 0
        var speedMult: CGFloat = 1.0
        var steeringRate: CGFloat = 3.0
        var wobbleTarget: CGFloat = 0
        var wobbleTimer: TimeInterval = 0
        var isFinished: Bool = false
        var node: SKSpriteNode
        var crashPenaltyMult: CGFloat = 1.0
        var penaltyRecoveryTimer: CGFloat = 0
        // Car-to-car contact
        var collisionCooldown: TimeInterval = 0
        var aggressionTimer: TimeInterval = 0
        var isTargetingPlayer: Bool = false
    }
    private var botStates: [BotState] = []
    private var botsFinishedBeforePlayer: Int = 0
    private var playerBumpCooldown: TimeInterval = 0   // global cooldown: can't be bumped again so soon
    private var playerStartX: CGFloat = 0              // grid-assigned start X for the player car

    private static let botTints: [SKColor] = [
        SKColor(red: 0.92, green: 0.15, blue: 0.10, alpha: 1.0),
        SKColor(red: 0.08, green: 0.82, blue: 0.22, alpha: 1.0),
        SKColor(red: 0.60, green: 0.08, blue: 0.95, alpha: 1.0),
    ]

    // MARK: - Scenery (trees on both sides, full-width mode only)
    private var sceneryNodes: [SKNode] = []
    private let scenerySpacing: CGFloat = 90
    private let sceneryCount:   Int     = 14   // per side; extra covers wrap gaps

    // (Road curve properties replaced by control-point system above)

    // Pause tracking (so we only fade once)
    private var wasPaused: Bool = false

    // Audio
    private var engineNode: SKAudioNode?
    private var engineStarted: Bool = false   // <- NEW: track if engine is running

    // MARK: - Init

    init(size: CGSize,
         side: Side,
         input: PlayerInput,
         coordinator: GameCoordinator,
         carPNG: String,
         isFullWidth: Bool = false,
         isEndlessMode: Bool = false,
         botCount: Int = 0,
         botDifficulty: BotDifficulty = .easy)
    {
        self.side = side
        self.input = input
        self.coordinator = coordinator
        self.chosenCarPNG = carPNG
        self.isFullWidth = isFullWidth
        self.isEndlessMode = isEndlessMode
        self.botCount     = isEndlessMode ? 0 : botCount
        self.botDifficulty = botDifficulty
        // Use current selected speed level for this scene
        self.difficulty = SettingsStore.shared.selectedSpeedLevel

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
        // Wider road in single-player so it fills the screen (no split companion lane)
        let roadWidthFrac: CGFloat = isFullWidth ? 0.86 : 0.70
        let roadInsetFrac: CGFloat = (1.0 - roadWidthFrac) / 2.0
        playableRect = CGRect(
            x: size.width * roadInsetFrac,
            y: marginTowardBottom,
            width: size.width * roadWidthFrac,
            height: size.height - marginTowardBottom - marginTowardTop
        )

        // Configure baseSpeed according to difficulty (Easy/Medium/Hard/Insane)
        configureBaseSpeed()

        // Angular road only in endless mode; solo race stays straight
        if isFullWidth && isEndlessMode { initRoadPoints() }

        // Grass background + road shoulder lines (full-width modes only)
        if isFullWidth { buildBackground() }

        // Road — path is built dynamically each frame so it bends with the curve
        roadNode = SKShapeNode()
        roadNode.fillColor   = SKColor(white: 0.18, alpha: 1.0)
        roadNode.strokeColor = SKColor(white: 1.0,  alpha: 0.50)  // bent shoulder lines for free
        roadNode.lineWidth   = 3
        roadNode.zPosition   = 5
        addChild(roadNode)
        updateRoadPath()    // set initial straight path

        // Scrolling tree scenery on both sides (full-width modes only)
        if isFullWidth { buildScenery() }

        // Center dashed line — hidden in endless mode (open road feel)
        buildDashes()
        if isEndlessMode { dashNodes.forEach { $0.alpha = 0 } }

        // Start / Finish — only built in the fixed-race modes; endless has no finish line
        if !isEndlessMode {
            buildCheckeredLines()
        }

        // Car (PNG or procedural; single placement path)
        let accent: SKColor = (side == .left) ? (Theme.p1SK ?? .red) : (Theme.p2SK ?? .blue)

        if usePNGCar {
            // Use the player’s chosen car from SettingsStore
            let carName = (side == .left)
                ? SettingsStore.shared.player1Car
                : SettingsStore.shared.player2Car

            carNode = makePNGCar(textureName: carName)
        } else {
            carNode = makeCar(color: accent)
        }

        // Common placement for both cars
        let carY: CGFloat = (side == .left)
            ? playableRect.minY + playableRect.height * 0.18
            : playableRect.maxY - playableRect.height * 0.18

        carNode.position = CGPoint(x: playableRect.midX, y: carY)
        initialCarY = carY     // <- remember for restarts

        if side == .right { carNode.zRotation = .pi }
        carNode.zPosition = 100
        addChild(carNode)

        // Spawn bot cars (solo race only; reset is handled in prepareForNewRound)
        botsFinishedBeforePlayer = 0
        buildBots()

        // Place START just in front of the car (toward driving direction) — only in fixed-race modes
        if let sl = startLine {
            let behindOffset: CGFloat = 28
            if side == .left {
                sl.position = CGPoint(x: playableRect.midX, y: carNode.position.y - behindOffset)
            } else {
                sl.position = CGPoint(x: playableRect.midX, y: carNode.position.y + behindOffset)
            }
        }

        distanceAdvanced = 0
        hasSignalledFinish = false

        if isEndlessMode {
            // No finish line, no progress bar — distance is tracked live via coordinator
        } else {
            // Distance bar
            addProgressBar()
            updateProgressFill(ratio: 0)

            // Finish distance: clean 30s run hits finish exactly at t=0 (for a clean run)
            let totalSeconds: CGFloat = 30
            totalTrackDistance = baseSpeed * totalSeconds

            if let fl = finishLine {
                if side == .left {
                    fl.position = CGPoint(x: playableRect.midX, y: carNode.position.y + totalTrackDistance)
                } else {
                    fl.position = CGPoint(x: playableRect.midX, y: carNode.position.y - totalTrackDistance)
                }
            }
        }

        // NOTE: we DO NOT start engine here anymore.
        engineStarted = false

        // Vignette overlay (over gameplay rect)
        ensureSlowVignette()

        // Reset
        lastUpdate = 0
        spawnAccum = 0
        speedMultiplier = 1
        dashPhase = 0
        elapsedRaceTime = 0
        layoutDashes()
        wasPaused = false
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if view != nil { didMove(to: view!) }
    }

    // MARK: - Difficulty setup

    private func configureBaseSpeed() {
        switch difficulty {
        case .easy:
            baseSpeed = 260
        case .medium:
            baseSpeed = 300
        case .hard:
            baseSpeed = 340
        case .insane:
            baseSpeed = 380
        }
    }

    // MARK: - Car builder (PNG or procedural)

    private func makeCar(color: SKColor) -> SKNode {
        let targetW = CAR_BASE_SIZE.width  * CAR_SCALE
        let targetH = CAR_BASE_SIZE.height * CAR_SCALE

        if USE_IMAGE_CAR {
            // Pick the right image by side
            let name = (side == .left) ? LEFT_CAR_IMAGE : RIGHT_CAR_IMAGE
            let tex  = SKTexture(imageNamed: name)
            tex.filteringMode = .linear

            // Preserve PNG aspect ratio but fit INSIDE the 30×50 box (scaled)
            let ar = tex.size().width / tex.size().height   // w/h
            var finalW = targetW
            var finalH = targetH
            if ar > (targetW / targetH) {
                // image is “wider” → cap width, reduce height to keep aspect
                finalH = finalW / ar
            } else {
                // image is “taller” → cap height, reduce width to keep aspect
                finalW = finalH * ar
            }

            let sprite = SKSpriteNode(texture: tex, size: CGSize(width: finalW, height: finalH))
            sprite.zPosition = 100
            sprite.colorBlendFactor = 0.0
            return sprite
        } else {
            // Your original drawn car at the same footprint (scaled)
            let car = SKNode()

            // Body
            let targetW = CAR_BASE_SIZE.width  * CAR_SCALE
            let targetH = CAR_BASE_SIZE.height * CAR_SCALE
            let body = SKShapeNode(rectOf: CGSize(width: targetW, height: targetH), cornerRadius: 6)
            body.fillColor = color
            body.strokeColor = .black
            body.lineWidth = 1.5
            body.zPosition = 30
            car.addChild(body)

            // Wheels (scaled proportionally)
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

            // Windshield
            let windshield = SKShapeNode(rectOf: CGSize(width: 20*CAR_SCALE, height: 10*CAR_SCALE), cornerRadius: 2*CAR_SCALE)
            windshield.fillColor = SKColor(cgColor: CGColor(red: 0.75, green: 0.9, blue: 1.0, alpha: 0.9))
            windshield.strokeColor = .clear
            windshield.position = CGPoint(x: 0, y: (targetH/2) - (10*CAR_SCALE))
            windshield.zPosition = 32
            car.addChild(windshield)

            // Rear lights
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
            path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: dashLen))
            let dash = SKShapeNode(path: path)
            dash.strokeColor = .white
            dash.lineWidth = 2
            dash.zPosition = 15 // above road, below checkers
            addChild(dash)
            dashNodes.append(dash)
        }
    }

    // MARK: - Angular road — control-point helpers

    /// Returns interpolated (leftX, rightX) for the road at a given screen Y.
    /// Points must be sorted ascending-Y (bottom → top).
    private func roadBounds(at y: CGFloat) -> (left: CGFloat, right: CGFloat)? {
        guard roadPoints.count >= 2 else { return nil }
        for i in 0..<(roadPoints.count - 1) {
            let lo = roadPoints[i], hi = roadPoints[i + 1]
            guard y >= lo.y && y <= hi.y else { continue }
            let t  = (hi.y == lo.y) ? 0 : (y - lo.y) / (hi.y - lo.y)
            return (lo.leftX  + (hi.leftX  - lo.leftX)  * t,
                    lo.rightX + (hi.rightX - lo.rightX) * t)
        }
        // Outside the array range — clamp to nearest end
        if y < roadPoints.first!.y { let p = roadPoints.first!; return (p.leftX, p.rightX) }
        let p = roadPoints.last!; return (p.leftX, p.rightX)
    }

    /// Rebuilds the road polygon from control points.
    /// Falls back to a plain rect in two-player (non-fullWidth) mode.
    private func updateRoadPath() {
        guard isFullWidth, roadPoints.count >= 2 else {
            roadNode.path = CGPath(roundedRect: playableRect, cornerWidth: 10,
                                   cornerHeight: 10, transform: nil)
            return
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: roadPoints[0].leftX, y: roadPoints[0].y))
        for pt in roadPoints.dropFirst() { path.addLine(to: CGPoint(x: pt.leftX,  y: pt.y)) }
        for pt in roadPoints.reversed()  { path.addLine(to: CGPoint(x: pt.rightX, y: pt.y)) }
        path.closeSubpath()
        roadNode.path = path
    }

    /// Populates the control-point array from scratch (straight road, full width).
    private func initRoadPoints() {
        roadPoints.removeAll()
        genLeft  = playableRect.minX
        genRight = playableRect.maxX
        genLeftDelta     = 0
        genRightDelta    = 0
        genSegsRemaining = 5   // 5 straight segments before first bend

        // Seed enough points to fill screen + buffer above and below
        let startY = playableRect.minY - pointSpacing * 2
        let endY   = playableRect.maxY + pointSpacing * 3
        var y = startY
        while y <= endY {
            roadPoints.append(RoadPoint(leftX: genLeft, rightX: genRight, y: y))
            y += pointSpacing
        }
    }

    /// Generates the next road control point at the top of the array,
    /// choosing a new angular behaviour when the current run expires.
    private func generateNextPoint() {
        if genSegsRemaining <= 0 { chooseNextBehaviour() }
        genSegsRemaining -= 1

        let minLeft:  CGFloat = 12
        let maxRight: CGFloat = size.width - 12
        let minWidth: CGFloat = playableRect.width * 0.30   // road can't get this narrow

        genLeft  += genLeftDelta
        genRight += genRightDelta

        // Bounce off screen/min-width walls and flip the delta
        if genLeft < minLeft  { genLeft  = minLeft;              genLeftDelta  = abs(genLeftDelta) }
        if genRight > maxRight { genRight = maxRight;            genRightDelta = -abs(genRightDelta) }
        if genRight - genLeft < minWidth {
            // Widen back out: push edges apart
            let mid = (genLeft + genRight) / 2
            genLeft  = mid - minWidth / 2; genLeftDelta  = -abs(genLeftDelta)
            genRight = mid + minWidth / 2; genRightDelta =  abs(genRightDelta)
        }

        let topY = (roadPoints.last?.y ?? playableRect.maxY) + pointSpacing
        roadPoints.append(RoadPoint(leftX: genLeft, rightX: genRight, y: topY))
    }

    /// Randomly picks the next angular road behaviour.
    private func chooseNextBehaviour() {
        // (leftDelta, rightDelta, minRun, maxRun)
        // Positive delta = edge moves RIGHT; negative = moves LEFT.
        typealias B = (CGFloat, CGFloat, Int, Int)
        let pool: [B] = [
            // Straight — weighted 3×
            ( 0,    0,   4, 7),
            ( 0,    0,   3, 6),
            ( 0,    0,   3, 5),
            // Symmetric bends (whole road shifts)
            (-58,  -58,  2, 4),   // sharp left
            ( 58,   58,  2, 4),   // sharp right
            (-35,  -35,  2, 4),   // gentle left
            ( 35,   35,  2, 4),   // gentle right
            // Width changes
            ( 40,  -40,  2, 3),   // squeeze narrow
            (-32,   32,  2, 3),   // open wide
            // Asymmetric — one edge straight, other tapers
            ( 55,    0,  2, 4),   // left edge cuts in
            (  0,  -55,  2, 4),   // right edge cuts in
            (-55,    0,  2, 4),   // left edge expands
            (  0,   55,  2, 4),   // right edge expands
            // Diagonal — edges move opposite directions unequally
            ( 50,  -15,  2, 3),   // aggressive left taper
            (-15,  -50,  2, 3),   // aggressive right taper
            ( 15,   50,  2, 3),   // aggressive right expand
        ]
        let b = pool.randomElement()!
        genLeftDelta     = b.0
        genRightDelta    = b.1
        genSegsRemaining = Int.random(in: b.2...b.3)
    }

    /// Positions dashes — each dash independently queries road bounds at its Y.
    private func layoutDashes() {
        for (i, dash) in dashNodes.enumerated() {
            let base = CGFloat(i) * dashSpacing
            let p = CGMutablePath()
            if side == .left {
                let yStart = playableRect.minY + base - dashPhase
                let cx     = roadBounds(at: yStart).map { ($0.left + $0.right) / 2 }
                             ?? playableRect.midX
                p.move(to: CGPoint(x: cx, y: yStart))
                p.addLine(to: CGPoint(x: cx, y: yStart + dashLen))
            } else {
                let yStart = playableRect.maxY - base + dashPhase
                let cx     = roadBounds(at: yStart).map { ($0.left + $0.right) / 2 }
                             ?? playableRect.midX
                p.move(to: CGPoint(x: cx, y: yStart))
                p.addLine(to: CGPoint(x: cx, y: yStart - dashLen))
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
                tile.position = CGPoint(x: -width/2 + tileW * (CGFloat(c) + 0.5),
                                        y: -height/2 + tileH * (CGFloat(r) + 0.5))
                node.addChild(tile)
            }
        }
        node.zPosition = 100
        return node
    }

    private func buildCheckeredLines() {
        let sl = checkered(width: playableRect.width * 0.8, height: 18)
        let fl = checkered(width: playableRect.width * 0.8, height: 18)
        sl.zPosition = 60
        fl.zPosition = 60
        addChild(sl)
        addChild(fl)
        startLine = sl
        finishLine = fl
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
            node.colorBlendFactor = 0.0  // keeps original PNG colors
        }
        return node
    }

    // MARK: - Bot builders & helpers

    private func buildBots() {
        for state in botStates { state.node.removeFromParent() }
        botStates.removeAll()

        // Spread all cars (player + bots) evenly across road width for grid start
        let totalCars  = botCount + 1
        let margin: CGFloat = carEdgePad + 20
        let roadLeft   = playableRect.minX + margin
        let roadRight  = playableRect.maxX - margin
        let slotWidth  = (roadRight - roadLeft) / CGFloat(totalCars)
        let playerSlot = (totalCars - 1) / 2   // player gets middle slot

        playerStartX       = roadLeft + slotWidth * CGFloat(playerSlot) + slotWidth / 2
        carNode.position.x = playerStartX

        guard botCount > 0, isFullWidth, !isEndlessMode else { return }

        // Remaining slots go to bots
        let botSlots = (0..<totalCars).filter { $0 != playerSlot }

        for i in 0..<min(botCount, 3) {
            let tint    = GameScene.botTints[i]
            let botNode = makePNGCar(textureName: SettingsStore.shared.player1Car, tint: tint)
            botNode.zPosition = 90 + CGFloat(i)

            let slot   = botSlots[i]
            let startX = roadLeft + slotWidth * CGFloat(slot) + slotWidth / 2
            botNode.position = CGPoint(x: startX, y: initialCarY)
            addChild(botNode)

            let (speedMult, steeringRate) = botParams(elapsed: 0)

            let state = BotState(
                distanceAdvanced: 0,     // same start line as player
                x: startX,
                speedMult: speedMult,
                steeringRate: steeringRate,
                wobbleTarget: CGFloat.random(in: -20...20),
                wobbleTimer: Double.random(in: 0...1.0),
                node: botNode
            )
            botStates.append(state)
        }
    }

    private func botParams(elapsed: TimeInterval) -> (speedMult: CGFloat, steeringRate: CGFloat) {
        switch botDifficulty {
        case .easy:       return (0.88, 1.4)   // slower, clumsy
        case .medium:     return (1.00, 3.0)   // matched speed, decent steering
        case .hard:       return (1.14, 5.0)   // genuinely faster + sharp
        case .relentless:
            let t = CGFloat(min(1.0, elapsed / 30.0))
            return (0.92 + 0.28 * t, 2.0 + 3.5 * t)   // 0.92→1.20, steering tightens
        }
    }

    private func updateBots(dt: TimeInterval, stageSpeedBoost: CGFloat) {
        // Decrement global player bump cooldown once per frame
        if playerBumpCooldown > 0 { playerBumpCooldown -= dt }

        for i in 0..<botStates.count {
            var bot = botStates[i]
            if bot.isFinished {
                bot.node.isHidden = true
                botStates[i] = bot
                continue
            }

            // Update speed + steering for this frame (relentless ramps both over time)
            let (speedMult, steeringRate) = botParams(elapsed: elapsedRaceTime)
            bot.speedMult    = speedMult
            bot.steeringRate = steeringRate

            // Crash-penalty recovery
            if bot.crashPenaltyMult < 0.999 {
                bot.penaltyRecoveryTimer += CGFloat(dt)
                let dur: CGFloat = 2.5
                let t = min(1.0, bot.penaltyRecoveryTimer / dur)
                bot.crashPenaltyMult = 0.40 + 0.60 * (1 - pow(1 - t, 2))
            }

            // Obstacle crash roll
            let failChance: Double
            switch botDifficulty {
            case .easy:       failChance = 0.80
            case .medium:     failChance = 0.50
            case .hard:       failChance = 0.15
            case .relentless: failChance = max(0.08, 0.55 - 0.47 * min(1.0, elapsedRaceTime / 30.0))
            }

            // Bot screen Y relative to player
            let botScreenY = initialCarY + CGFloat(bot.distanceAdvanced - distanceAdvanced)

            if bot.crashPenaltyMult >= 0.999 {
                for obs in obstacles {
                    let oy = obs.position.y
                    let ahead = oy > botScreenY && oy < botScreenY + 75
                    if ahead && abs(obs.position.x - bot.x) < 30 {
                        if Double.random(in: 0...1) < failChance {
                            bot.crashPenaltyMult = 0.40
                            bot.penaltyRecoveryTimer = 0
                        }
                        break
                    }
                }
            }

            // Advance bot distance: base speed × difficulty mult × crash penalty × stage boost
            let botSpeed = baseSpeed * bot.speedMult * bot.crashPenaltyMult * stageSpeedBoost
            bot.distanceAdvanced += botSpeed * CGFloat(dt)

            // ── Aggression (Hard / Relentless only) ──────────────────────────
            bot.aggressionTimer -= dt
            if bot.aggressionTimer <= 0 {
                let aggressionChance: Double
                switch botDifficulty {
                case .easy, .medium: aggressionChance = 0.0
                case .hard:          aggressionChance = 0.25
                case .relentless:    aggressionChance = min(0.55, 0.20 + 0.35 * min(1.0, elapsedRaceTime / 30.0))
                }
                bot.isTargetingPlayer = Double.random(in: 0...1) < aggressionChance
                bot.aggressionTimer   = Double.random(in: 1.5...3.0)
            }

            // Wobble refresh (only when NOT targeting player)
            bot.wobbleTimer += dt
            let wobbleInterval: TimeInterval
            let wobbleRange: CGFloat
            switch botDifficulty {
            case .easy:       wobbleInterval = 0.9;  wobbleRange = 60
            case .medium:     wobbleInterval = 1.5;  wobbleRange = 30
            case .hard:       wobbleInterval = 2.2;  wobbleRange = 14
            case .relentless:
                wobbleInterval = 1.8
                wobbleRange = max(8, 35 - 27 * CGFloat(min(1.0, elapsedRaceTime / 30.0)))
            }
            if bot.wobbleTimer >= wobbleInterval {
                bot.wobbleTimer = 0
                bot.wobbleTarget = bot.isTargetingPlayer ? 0 : CGFloat.random(in: -wobbleRange...wobbleRange)
            }

            // Target X — switch to chasing player when aggressive
            let midX = roadBounds(at: botScreenY).map { ($0.left + $0.right) / 2 } ?? playableRect.midX
            var targetX: CGFloat
            if bot.isTargetingPlayer {
                // Aim at player's X with small noise so it's not pixel-perfect
                targetX = carNode.position.x + CGFloat.random(in: -12...12)
            } else {
                targetX = midX + bot.wobbleTarget
            }

            // Obstacle avoidance steering
            let avoidProb: Double
            switch botDifficulty {
            case .easy:       avoidProb = 0.20
            case .medium:     avoidProb = 0.55
            case .hard:       avoidProb = 0.88
            case .relentless: avoidProb = min(0.92, 0.45 + 0.47 * min(1.0, elapsedRaceTime / 30.0))
            }
            for obs in obstacles {
                let oy = obs.position.y
                if oy > botScreenY && oy < botScreenY + 80 && Double.random(in: 0...1) < avoidProb {
                    let dx = obs.position.x - bot.x
                    if abs(dx) < 30 {
                        targetX = bot.x + (dx < 0 ? 45 : -45)
                    }
                }
            }

            // Steer toward target
            let newX = bot.x + (targetX - bot.x) * bot.steeringRate * CGFloat(dt)
            if let bounds = roadBounds(at: botScreenY) {
                bot.x = max(bounds.left + carEdgePad, min(bounds.right - carEdgePad, newX))
            } else {
                bot.x = max(roadMinX, min(roadMaxX, newX))
            }

            // ── Car-to-car collision ──────────────────────────────────────────
            bot.collisionCooldown -= dt
            let cDx = abs(bot.x - carNode.position.x)
            let cDy = abs(botScreenY - carNode.position.y)
            if bot.collisionCooldown <= 0 && cDx < 26 && cDy < 36 {
                bot.collisionCooldown = 2.0

                // Visual: both cars flash
                let flash = SKAction.sequence([
                    .fadeAlpha(to: 0.35, duration: 0.05),
                    .fadeAlpha(to: 1.00, duration: 0.18)
                ])
                carNode.run(flash)
                bot.node.run(flash)
                playCrash()

                // Bump player (if cooldown expired)
                applyBumpPenalty()

                // Also slow the bot that hit us
                if bot.crashPenaltyMult > 0.65 {
                    bot.crashPenaltyMult = 0.65
                    bot.penaltyRecoveryTimer = 0
                }

                // Separate the cars laterally so they don't get stuck
                let push: CGFloat = 18
                let playerIsLeft = carNode.position.x < bot.x
                carNode.position.x += playerIsLeft ? -push : push
                bot.x              += playerIsLeft ?  push : -push
            }

            // Show/hide + position
            let onScreen = botScreenY > playableRect.minY - 100 && botScreenY < playableRect.maxY + 100
            bot.node.isHidden = !onScreen
            if onScreen {
                bot.node.position = CGPoint(x: bot.x, y: botScreenY)
            }

            // Check finish
            if !hasSignalledFinish && bot.distanceAdvanced >= totalTrackDistance {
                bot.isFinished = true
                botsFinishedBeforePlayer += 1
            }

            botStates[i] = bot
        }
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

    // Call this when a new round starts (if you keep the same scene instance)
    func prepareForNewRound() {
        // Clear obstacles
        obstacles.forEach { $0.removeFromParent() }
        obstacles.removeAll()

        // Reset timers/state
        lastUpdate = 0
        spawnAccum = 0
        speedMultiplier = 1
        dashPhase = 0
        elapsedRaceTime = 0
        distanceAdvanced = 0
        hasSignalledFinish = false
        isRecovering = false
        boostCharge = 0

        botsFinishedBeforePlayer = 0
        playerBumpCooldown = 0
        buildBots()

        // Reset car to grid start position
        carNode.removeAllActions()
        carNode.position = CGPoint(x: playerStartX, y: initialCarY)
        carNode.zRotation = (side == .right) ? .pi : 0

        // Dashes back to base placement
        layoutDashes()

        // Reset road control points (endless only; solo race stays straight)
        if isFullWidth && isEndlessMode { initRoadPoints() }
        updateRoadPath()

        // Rebuild scenery so trees get fresh random positions each run
        if isFullWidth { buildScenery() }

        if isEndlessMode {
            // Endless mode: no finish line, no progress bar — just reset distance tracking
            distanceAdvanced = 0
        } else {
            // Progress bar back to 0
            updateProgressFill(ratio: 0)

            // --- Start line: recreate if nil, otherwise ensure it's in the scene
            let behind: CGFloat = 28
            if startLine == nil {
                let sl = checkered(width: playableRect.width * 0.8, height: 18)
                sl.zPosition = 60
                addChild(sl)
                startLine = sl
            } else if startLine?.parent == nil, let sl = startLine {
                addChild(sl)
            }
            if let sl = startLine {
                if side == .left {
                    sl.position = CGPoint(x: playableRect.midX, y: carNode.position.y - behind)
                } else {
                    sl.position = CGPoint(x: playableRect.midX, y: carNode.position.y + behind)
                }
            }

            // --- Finish line: always recreate fresh
            finishLine?.removeFromParent()
            let fl = checkered(width: playableRect.width * 0.8, height: 18)
            fl.zPosition = 60
            addChild(fl)
            finishLine = fl

            let totalSeconds: CGFloat = 30
            totalTrackDistance = baseSpeed * totalSeconds
            if side == .left {
                fl.position = CGPoint(x: playableRect.midX, y: carNode.position.y + totalTrackDistance)
            } else {
                fl.position = CGPoint(x: playableRect.midX, y: carNode.position.y - totalTrackDistance)
            }
        }

        // Make sure vignette is invisible at round start
        slowVignette?.removeAllActions()
        slowVignette?.alpha = 0.0

        // Engine back to normal volume (if currently attached)
        engineNode?.run(.changeVolume(to: 0.45, duration: 0.0))

        // 🔁 Engine reset for new round
        engineStarted = false
        stopEngineLoop()
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

    // MARK: - Background & Scenery

    /// Fills the screen with grass green and adds white road-shoulder lines.
    private func buildBackground() {
        // Grass background (sits behind everything)
        let bg = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        bg.fillColor = SKColor(red: 0.18, green: 0.40, blue: 0.10, alpha: 1.0)
        bg.strokeColor = .clear
        bg.zPosition = 0
        addChild(bg)

        // Darker strip tight against each road edge — like a dirt/gravel shoulder
        for sign: CGFloat in [-1, 1] {
            let edgeX = sign > 0 ? playableRect.maxX : playableRect.minX
            let stripW: CGFloat = size.width * 0.06
            let stripX = sign > 0 ? edgeX : edgeX - stripW
            let strip = SKShapeNode(rect: CGRect(x: stripX, y: 0, width: stripW, height: size.height))
            strip.fillColor = SKColor(red: 0.55, green: 0.44, blue: 0.20, alpha: 1.0)   // sandy dirt
            strip.strokeColor = .clear
            strip.zPosition = 1
            addChild(strip)
        }

        // Road shoulder lines are now part of roadNode's stroke (they bend with the road).
    }

    /// Builds `sceneryCount` trees on each side of the road, evenly spaced vertically.
    private func buildScenery() {
        sceneryNodes.forEach { $0.removeFromParent() }
        sceneryNodes.removeAll()

        let leftBand  = (min: CGFloat(4),             max: playableRect.minX - 6)
        let rightBand = (min: playableRect.maxX + 6,  max: size.width - 4)

        for i in 0..<sceneryCount {
            let yBase = playableRect.minY + CGFloat(i) * scenerySpacing

            // Left tree
            if leftBand.max > leftBand.min {
                let lx = CGFloat.random(in: leftBand.min ... leftBand.max)
                let lt = makeTree(scale: CGFloat.random(in: 0.80 ... 1.20))
                lt.position = CGPoint(x: lx, y: yBase)
                lt.zPosition = 4
                addChild(lt)
                sceneryNodes.append(lt)
            }

            // Right tree
            if rightBand.max > rightBand.min {
                let rx = CGFloat.random(in: rightBand.min ... rightBand.max)
                let rt = makeTree(scale: CGFloat.random(in: 0.80 ... 1.20))
                rt.position = CGPoint(x: rx, y: yBase)
                rt.zPosition = 4
                addChild(rt)
                sceneryNodes.append(rt)
            }
        }
    }

    /// Procedural pixel-art style tree — layered foliage circles on a trunk.
    private func makeTree(scale: CGFloat = 1.0) -> SKNode {
        let tree = SKNode()

        // Trunk
        let trunk = SKShapeNode(rectOf: CGSize(width: 7 * scale, height: 18 * scale), cornerRadius: 2)
        trunk.fillColor = SKColor(red: 0.32, green: 0.18, blue: 0.06, alpha: 1.0)
        trunk.strokeColor = .clear
        trunk.position = CGPoint(x: 0, y: -7 * scale)
        trunk.zPosition = 1
        tree.addChild(trunk)

        // Three overlapping foliage blobs (bottom-large → top-small for depth)
        let layers: [(radius: CGFloat, yOff: CGFloat)] = [
            (19 * scale,  4 * scale),
            (15 * scale, 14 * scale),
            (11 * scale, 22 * scale),
        ]
        for (radius, yOff) in layers {
            let blob = SKShapeNode(circleOfRadius: radius)
            let g = CGFloat.random(in: 0.38 ... 0.60)
            blob.fillColor   = SKColor(red: 0.04, green: g, blue: 0.04, alpha: 1.0)
            blob.strokeColor = SKColor(red: 0.02, green: g * 0.65, blue: 0.02, alpha: 0.7)
            blob.lineWidth   = 1
            blob.position    = CGPoint(x: CGFloat.random(in: -3 ... 3) * scale, y: yOff)
            blob.zPosition   = 2
            tree.addChild(blob)
        }

        return tree
    }

    /// Scrolls scenery nodes vertically with the world and wraps them.
    /// Trees keep their fixed X columns — the road bends past them, which IS the parallax.
    private func updateScenery(dy: CGFloat) {
        let wrapHeight = playableRect.height + scenerySpacing * 2
        for node in sceneryNodes {
            node.position.y += dy
            // No X drift: trees are rooted; the road polygon shifts underneath them.
            if side == .left {
                if node.position.y < playableRect.minY - scenerySpacing {
                    node.position.y += wrapHeight
                }
            } else {
                if node.position.y > playableRect.maxY + scenerySpacing {
                    node.position.y -= wrapHeight
                }
            }
        }
    }

    // MARK: - Obstacles

    private func spawnObstacle() {
        // Expanded obstacle set
        enum O {
            case cone
            case box
            case tumbleweed
            case squirrel
            case pothole
            case rock
            case oilSlick
            case slowTruck
        }

        // Pick which obstacles are allowed per difficulty
        let pool: [O]
        switch difficulty {
        case .easy:
            // Gentle mix
            pool = [.cone, .box, .tumbleweed, .squirrel]
        case .medium:
            // Slightly more intense
            pool = [.cone, .box, .tumbleweed, .squirrel, .pothole, .rock]
        case .hard:
            // Busier + trickier shapes
            pool = [.cone, .box, .tumbleweed, .squirrel, .pothole, .rock, .oilSlick]
        case .insane:
            // Everything, including wider “truck” block
            pool = [.cone, .box, .tumbleweed, .squirrel, .pothole, .rock, .oilSlick, .slowTruck]
        }

        let t: O = pool.randomElement()!

        let node: SKNode
        switch t {
        case .cone:
            // Traffic cone (triangle)
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
            // Crate
            let box = SKShapeNode(rectOf: CGSize(width: 18, height: 18), cornerRadius: 3)
            box.fillColor = SKColor(red: 0.75, green: 0.55, blue: 0.30, alpha: 1.0)
            box.strokeColor = .clear
            node = box

        case .tumbleweed:
            // Round tumbleweed
            let weed = SKShapeNode(circleOfRadius: 10)
            weed.fillColor = SKColor(red: 0.65, green: 0.50, blue: 0.30, alpha: 1.0)
            weed.strokeColor = .white.withAlphaComponent(0.2)
            node = weed

        case .squirrel:
            // Emoji squirrel
            let label = SKLabelNode(text: "🐿️")
            label.fontSize = 22
            node = label

        case .pothole:
            // Dark pothole in the road
            let hole = SKShapeNode(circleOfRadius: 11)
            hole.fillColor = SKColor(white: 0.05, alpha: 1.0)
            hole.strokeColor = SKColor(white: 0.6, alpha: 0.5)
            hole.lineWidth = 1.5
            node = hole

        case .rock:
            // Small rock / boulder
            let rock = SKShapeNode(circleOfRadius: 9)
            rock.fillColor = SKColor(white: 0.55, alpha: 1.0)
            rock.strokeColor = SKColor(white: 0.2, alpha: 0.7)
            rock.lineWidth = 1.2
            node = rock

        case .oilSlick:
            // Slippery oil patch (wider + low contrast)
            let slickSize = CGSize(width: 32, height: 14)
            let slick = SKShapeNode(rectOf: slickSize, cornerRadius: 6)
            slick.fillColor = SKColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1.0)
            slick.strokeColor = SKColor(white: 1.0, alpha: 0.15)
            slick.lineWidth = 1
            node = slick

        case .slowTruck:
            // Wider “truck” style block (acts like a big roadblock)
            let truckSize = CGSize(width: 26, height: 30)
            let truck = SKShapeNode(rectOf: truckSize, cornerRadius: 4)
            truck.fillColor = SKColor(red: 0.20, green: 0.40, blue: 0.80, alpha: 1.0)
            truck.strokeColor = SKColor(white: 0.1, alpha: 0.9)
            truck.lineWidth = 1.5

            // Tiny cab hint on top
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

        // Per-type idle animation
        switch t {
        case .tumbleweed:
            node.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.9)))
        case .cone:
            node.run(.repeatForever(.sequence([
                .rotate(byAngle:  0.18, duration: 0.35),
                .rotate(byAngle: -0.36, duration: 0.70),
                .rotate(byAngle:  0.18, duration: 0.35)
            ])))
        case .squirrel:
            node.run(.repeatForever(.sequence([
                .scale(to: 1.25, duration: 0.28),
                .scale(to: 0.88, duration: 0.28)
            ])))
        case .oilSlick:
            node.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0.55),
                .fadeAlpha(to: 1.00, duration: 0.55)
            ])))
        case .slowTruck:
            // Truck bobs slightly side-to-side (like it's steering)
            node.run(.repeatForever(.sequence([
                .moveBy(x:  4, y: 0, duration: 0.5),
                .moveBy(x: -8, y: 0, duration: 1.0),
                .moveBy(x:  4, y: 0, duration: 0.5)
            ])))
        default:
            break
        }

        // Spawn within the actual road bounds at the horizon
        let spawnY: CGFloat = (side == .left) ? playableRect.maxY + 30 : playableRect.minY - 30
        let spawnBounds = isFullWidth
            ? roadBounds(at: spawnY) ?? (left: playableRect.minX, right: playableRect.maxX)
            : (left: playableRect.minX, right: playableRect.maxX)
        let x = CGFloat.random(in: (spawnBounds.left + carEdgePad)
                                    ... (spawnBounds.right - carEdgePad))
        node.position = CGPoint(x: x, y: spawnY)

        addChild(node)
        obstacles.append(node)
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        // --- Delta time ---
        if lastUpdate == 0 { lastUpdate = currentTime; return }
        let dt = currentTime - lastUpdate
        lastUpdate = currentTime

        // --- Global pause handling (freeze scene logic) ---
        if coordinator?.isPaused == true {
            if !wasPaused {
                stopEngineLoop()
                engineStarted = false
                wasPaused = true
            }
            return
        } else if wasPaused {
            // Only resume engine if race is actually running
            if coordinator?.raceStarted == true {
                startEngineLoop()
                engineStarted = true
            }
            wasPaused = false
        }

        // Allow lateral movement even before race starts
        applyLateralMovement(dt: dt)

        // === COUNTDOWN (race not started yet) ===
        if coordinator?.raceStarted != true {
            // Ensure engines are OFF during countdown
            if engineStarted {
                stopEngineLoop()
                engineStarted = false
            }

            // Keep the start line BEHIND the car (car sits visually on top)
            if let sl = startLine {
                let behind: CGFloat = 28
                if side == .left {
                    sl.position = CGPoint(x: playableRect.midX, y: carNode.position.y - behind)
                } else {
                    sl.position = CGPoint(x: playableRect.midX, y: carNode.position.y + behind)
                }
            }

            // Make sure progress looks reset while waiting (fixed-race only)
            if !isEndlessMode { updateProgressFill(ratio: 0) }
            return
        }

        // If this lane already finished, keep it frozen on the checker
        if hasSignalledFinish {
            return
        }

        // If the round ended after we started (timer or other lane), stop updates
        if coordinator?.roundActive == false {
            stopEngineLoop()
            engineStarted = false
            return
        }

        // === ACTIVE RACE ===

        // Start engine loop once when race actually starts
        if !engineStarted {
            startEngineLoop()
            engineStarted = true
        }

        // Track elapsed race time for stage difficulty
        elapsedRaceTime += dt

        // Scroll road control points and regenerate at the horizon (full-width only)

        // Per-stage multipliers — endless mode climbs forever; fixed race uses 3 stages
        var stageSpeedBoost: CGFloat = 1.0
        var stageSpawnScale: Double = 1.0

        if isEndlessMode {
            // Continuous escalation: +25% speed per 60 s (uncapped)
            stageSpeedBoost = 1.0 + CGFloat(elapsedRaceTime / 60.0) * 0.25
            // Spawn density ramps to a floor of 0.15x at ~90 s
            stageSpawnScale = max(0.15, 1.0 - (elapsedRaceTime / 90.0) * 0.85)
            // Report live distance to coordinator (100 pts ≈ 1 m)
            let meters = Int(distanceAdvanced / 100)
            coordinator?.updateEndlessDistance(meters)
        } else {
            // Stage 0/1/2 for [0–10), [10–20), [20–30] seconds
            let stage = min(2, Int(elapsedRaceTime / 10.0))
            switch stage {
            case 0:
                stageSpeedBoost = 1.0
                stageSpawnScale = 1.0
            case 1:
                stageSpeedBoost = 1.15   // a bit faster mid-race
                stageSpawnScale = 0.85   // spawn slightly more often
            default:
                stageSpeedBoost = 1.30   // fastest in last 10s
                stageSpawnScale = 0.70   // most obstacles
            }
        }

        // Extra multipliers from selected difficulty
        let diffBoost: CGFloat
        let diffSpawnScale: Double
        switch difficulty {
        case .easy:
            diffBoost = 1.0
            diffSpawnScale = 1.0        // baseline density
        case .medium:
            diffBoost = 1.10
            diffSpawnScale = 0.65       // ~35% more obstacles than Easy
        case .hard:
            diffBoost = 1.20
            diffSpawnScale = 0.45       // roughly 2× Easy density
        case .insane:
            diffBoost = 1.30
            diffSpawnScale = 0.35       // chaos: lots of obstacles
        }

        let combinedSpawnScale = stageSpawnScale * diffSpawnScale

        let worldDir: CGFloat = (side == .left) ? -1.0 : +1.0

        // Nitro boost (only in solo-with-bots mode)
        let isBoosting = botCount > 0 && !isEndlessMode
                      && (input?.p1Boost == true) && boostCharge > 0
        if isBoosting {
            boostCharge = max(0, boostCharge - boostDrainRate * CGFloat(dt))
        }
        coordinator?.boostCharge = boostCharge

        let boostFactor: CGFloat = isBoosting ? boostSpeedMult : 1.0
        let speed = baseSpeed * speedMultiplier * stageSpeedBoost * diffBoost * boostFactor
        let dy = worldDir * speed * CGFloat(dt)

        // Distance tracking
        distanceAdvanced += abs(dy)

        if isEndlessMode {
            // Endless: no finish line — distance is reported to coordinator each frame (above)
        } else {
            // Fixed race: update progress bar and check for finish
            let ratio = min(distanceAdvanced / totalTrackDistance, 1.0)
            updateProgressFill(ratio: ratio)

            if !hasSignalledFinish && ratio >= 1.0 {
                hasSignalledFinish = true
                coordinator?.playerFinishPosition = botsFinishedBeforePlayer + 1

                if side == .left {
                    coordinator?.markFinished(player: 1)
                } else {
                    coordinator?.markFinished(player: 2)
                }

                stopEngineLoop()
                engineStarted = false
                return
            }
        }

        // Center dashed line via PHASE (never flickers)
        dashPhase = (dashPhase + abs(dy)).truncatingRemainder(dividingBy: dashSpacing)

        if isFullWidth {
            // Angular road updates only in endless mode; solo race is straight
            if isEndlessMode {
                for i in 0..<roadPoints.count { roadPoints[i].y += dy }
                let cutoff = playableRect.minY - pointSpacing * 2
                roadPoints.removeAll { $0.y < cutoff }
                let horizon = playableRect.maxY + pointSpacing * 3
                while roadPoints.last.map({ $0.y }) ?? 0 < horizon {
                    generateNextPoint()
                }
            }

            updateRoadPath()
            layoutDashes()
            updateScenery(dy: dy)
            if !botStates.isEmpty { updateBots(dt: dt, stageSpeedBoost: stageSpeedBoost) }
        } else {
            layoutDashes()
        }

        // Move checkered lines with the world (start line exists in all modes; finish only in fixed race)
        if let sl = startLine { sl.position.y += dy }
        finishLine?.position.y += dy

        // Remove start line once it scrolls past player's edge
        if let sl = startLine {
            if side == .left, sl.parent != nil, sl.position.y < playableRect.minY - 40 {
                sl.removeFromParent()
            } else if side == .right, sl.parent != nil, sl.position.y > playableRect.maxY + 40 {
                sl.removeFromParent()
            }
        }

        // Spawn & move obstacles + scoring clean passes
        spawnAccum += dt
        if spawnAccum >= spawnInterval {
            spawnAccum = 0
            // Slightly faster base rhythm, then scaled by difficulty + stage
            let baseInterval = Double.random(in: 0.9...1.4)   // was 1.2...1.8
            spawnInterval = baseInterval * combinedSpawnScale
            spawnObstacle()
        }

        var toRemove: [SKNode] = []
        for ob in obstacles {
            ob.position.y += dy

            // Collision (mark touched + feedback once)
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
                    playCrash()
                    if isEndlessMode {
                        applyBriefCrashFeedback()
                        coordinator?.playerLostLife()
                    } else {
                        applySmoothPenalty()
                    }
                }
            }

            // Score as soon as an untouched obstacle crosses the car
            var scored = (ob.userData?["scored"] as? Bool) ?? false
            if !touched && !scored {
                if side == .left {
                    if ob.position.y <= (carNode.position.y - 12) {
                        coordinator?.addScore(player1: true, points: 1)
                        ob.userData?["scored"] = true
                        scored = true
                        // Earn boost charge for each clean dodge
                        if botCount > 0 && !isEndlessMode {
                            boostCharge = min(boostMax, boostCharge + boostFillPerDodge)
                        }
                    }
                } else {
                    if ob.position.y >= (carNode.position.y + 12) {
                        coordinator?.addScore(player1: false, points: 1)
                        ob.userData?["scored"] = true
                        scored = true
                    }
                }
            }

            // Off-screen cleanup (no scoring here)
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
            // mirrored for top player
            if input?.p2Left  == true { moveX += vx }
            if input?.p2Right == true { moveX -= vx }
        }
        // Clamp to road bounds at the car's current Y (follows angular road shape)
        let newX = carNode.position.x + moveX * CGFloat(dt)
        if isFullWidth, let bounds = roadBounds(at: carNode.position.y) {
            carNode.position.x = max(bounds.left + carEdgePad,
                                     min(bounds.right - carEdgePad, newX))
        } else {
            carNode.position.x = max(roadMinX, min(roadMaxX, newX))
        }
    }

    // MARK: - Endless mode: brief crash flash (no speed change, just visual drama)
    private func applyBriefCrashFeedback() {
        // Red vignette flash
        slowVignette?.removeAllActions()
        slowVignette?.run(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.06),
            .fadeAlpha(to: 0.0,  duration: 0.40)
        ]))
        // Duck engine briefly
        engineNode?.run(.sequence([
            .changeVolume(to: 0.08, duration: 0.06),
            .changeVolume(to: 0.45, duration: 0.35)
        ]))
    }

    // MARK: - Car-to-car bump (lighter penalty, 1.2 s)
    private func applyBumpPenalty() {
        guard playerBumpCooldown <= 0 else { return }
        playerBumpCooldown = 2.0

        let minMul: CGFloat = 0.60
        speedMultiplier = min(speedMultiplier, minMul)

        // Orange-tinted vignette to distinguish from obstacle hits (red)
        slowVignette?.removeAllActions()
        slowVignette?.run(.sequence([
            .fadeAlpha(to: 0.28, duration: 0.06),
            .fadeAlpha(to: 0.0,  duration: 0.45)
        ]))
        engineNode?.run(.sequence([
            .changeVolume(to: 0.15, duration: 0.08),
            .changeVolume(to: 0.45, duration: 0.30)
        ]))

        removeAction(forKey: "bump")
        let steps = 60
        let stepDur = 1.2 / Double(steps)
        var i = 0
        let action = SKAction.repeat(SKAction.sequence([
            SKAction.run { [weak self] in
                guard let self else { return }
                i += 1
                let t = min(1.0, CGFloat(i) / CGFloat(steps))
                let eased = 1 - pow(1 - t, 2)
                self.speedMultiplier = max(self.speedMultiplier, minMul + (1.0 - minMul) * eased)
            },
            SKAction.wait(forDuration: stepDur)
        ]), count: steps)

        run(action, withKey: "bump")
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

        // Desaturate car (tint gray) — ONLY for procedural car
        if !usePNGCar {
            carNode.removeAction(forKey: "recoverTint")
            let tintDown = SKAction.colorize(with: .gray, colorBlendFactor: 0.7, duration: 0.12)
            tintDown.timingMode = .easeOut
            carNode.run(tintDown, withKey: "recoverTint")
        }
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
            // Restore visuals — ONLY for procedural car
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
        // Respect effects toggle
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
            .changeVolume(to: 0.0, duration: 0.5),  // smooth fade out
            .removeFromParent()
        ]))
        engineNode = nil
    }
}
