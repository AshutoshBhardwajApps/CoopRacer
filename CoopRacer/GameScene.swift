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
    private var engineStarted: Bool = false   // <- NEW: track if engine is running

    // MARK: - Init

    init(size: CGSize,
         side: Side,
         input: PlayerInput,
         coordinator: GameCoordinator,
         carPNG: String)
    {
        self.side = side
        self.input = input
        self.coordinator = coordinator
        self.chosenCarPNG = carPNG
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
        playableRect = CGRect(
            x: size.width * 0.15,
            y: marginTowardBottom,
            width: size.width * 0.70,
            height: size.height - marginTowardBottom - marginTowardTop
        )

        // Configure baseSpeed according to difficulty (Easy/Medium/Hard/Insane)
        configureBaseSpeed()

        // Road (grey so wheels pop)
        roadNode = SKShapeNode(rect: playableRect, cornerRadius: 10)
        roadNode.fillColor = SKColor(white: 0.18, alpha: 1.0)
        roadNode.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        roadNode.lineWidth = 2
        roadNode.zPosition = 5
        addChild(roadNode)

        // Center dashed line (phase-driven, *never* flickers)
        buildDashes()

        // Start / Finish (high z so always visible)
        buildCheckeredLines()

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

        // Place START just in front of the car (toward driving direction)
        let behindOffset: CGFloat = 28
        if side == .left {
            // bottom player drives UP → checker sits BELOW the car
            startLine.position = CGPoint(x: playableRect.midX,
                                         y: carNode.position.y - behindOffset)
        } else {
            // top player drives DOWN → checker sits ABOVE the car
            startLine.position = CGPoint(x: playableRect.midX,
                                         y: carNode.position.y + behindOffset)
        }

        // Distance bar
        addProgressBar()
        updateProgressFill(ratio: 0)

        // Finish distance: clean 30s run hits finish exactly at t=0 (for a clean run)
        let totalSeconds: CGFloat = 30
        totalTrackDistance = baseSpeed * totalSeconds
        distanceAdvanced = 0
        hasSignalledFinish = false

        if side == .left {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + totalTrackDistance)
        } else {
            finishLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - totalTrackDistance)
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
        layoutDashes() // initial placement
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

    // Position dashes using a phase that mirrors per side
    private func layoutDashes() {
        for (i, dash) in dashNodes.enumerated() {
            let base = CGFloat(i) * dashSpacing

            let p = CGMutablePath()
            if side == .left {
                // RED (bottom): dashes should visually move DOWN as time passes
                let yStart = playableRect.minY + base - dashPhase
                let yEnd   = yStart + dashLen
                p.move(to: CGPoint(x: playableRect.midX, y: yStart))
                p.addLine(to: CGPoint(x: playableRect.midX, y: yEnd))
            } else {
                // BLUE (top): mirrored — dashes should visually move UP as time passes
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
        // Put them under the car
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
            node.colorBlendFactor = 0.0  // keeps original PNG colors
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

        // Reset car to original starting lane center
        carNode.removeAllActions()
        carNode.position = CGPoint(x: playableRect.midX, y: initialCarY)
        carNode.zRotation = (side == .right) ? .pi : 0

        // Progress bar back to 0
        updateProgressFill(ratio: 0)

        // Dashes back to base placement
        layoutDashes()

        // --- Start line: recreate if nil, otherwise ensure it's in the scene
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

        // --- Finish line: always recreate fresh
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
            let behind: CGFloat = 28
            if side == .left {
                startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y - behind)
            } else {
                startLine.position = CGPoint(x: playableRect.midX, y: carNode.position.y + behind)
            }

            // Make sure progress looks reset while waiting
            updateProgressFill(ratio: 0)
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

        // Stage 0/1/2 for [0–10), [10–20), [20–30] seconds
        let stage = min(2, Int(elapsedRaceTime / 10.0))

        // Per-stage multipliers (ramp every 10s)
        var stageSpeedBoost: CGFloat = 1.0
        var stageSpawnScale: Double = 1.0

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
        let speed = baseSpeed * speedMultiplier * stageSpeedBoost * diffBoost
        let dy = worldDir * speed * CGFloat(dt)

        // Distance + progress bar
        distanceAdvanced += abs(dy)
        let ratio = min(distanceAdvanced / totalTrackDistance, 1.0)
        updateProgressFill(ratio: ratio)

        // ✅ Notify coordinator when this lane reaches the checker, and freeze this lane
        if !hasSignalledFinish && ratio >= 1.0 {
            hasSignalledFinish = true

            if side == .left {
                coordinator?.markFinished(player: 1)
            } else {
                coordinator?.markFinished(player: 2)
            }

            // Stop engine sound for this lane once finished
            stopEngineLoop()
            engineStarted = false
            // Keep car sitting at the finish line; no more scrolling for this lane
            return
        }

        // Center dashed line via PHASE (never flickers)
        dashPhase = (dashPhase + abs(dy)).truncatingRemainder(dividingBy: dashSpacing)
        layoutDashes()

        // Move checkered lines with the world
        startLine.position.y += dy
        finishLine.position.y += dy

        // Remove start line once it scrolls past player's edge
        if side == .left, startLine.parent != nil, startLine.position.y < playableRect.minY - 40 {
            startLine.removeFromParent()
        } else if side == .right, startLine.parent != nil, startLine.position.y > playableRect.maxY + 40 {
            startLine.removeFromParent()
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
                    applySmoothPenalty()
                    playCrash()
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
