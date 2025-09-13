
import SpriteKit

final class GameScene: SKScene {
    enum Side { case left, right }

    private let side: Side
    private weak var input: PlayerInput?

    private let car = SKShapeNode(rectOf: CGSize(width: 24, height: 40), cornerRadius: 6)
    private var laneWidth: CGFloat { size.width * 0.40 } // margin left/right
    private var speedY: CGFloat = 220 // pts/sec
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
        // Track boundaries (simple guide rails)
        let inner = SKShapeNode(rectOf: CGSize(width: size.width * 0.70, height: size.height * 0.90), cornerRadius: 8)
        inner.strokeColor = side == .left ? .red : .blue
        inner.lineWidth = 2
        inner.alpha = 0.7
        inner.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(inner)

        // Car
        car.fillColor = side == .left ? .red : .blue
        car.strokeColor = .clear
        car.position = CGPoint(x: size.width/2, y: size.height*0.25)
        addChild(car)

        // Scrolling lane markers
        for i in 0..<12 {
            addLaneDash(y: CGFloat(i) * 80.0)
        }
    }

    private func addLaneDash(y: CGFloat) {
        let path = CGMutablePath()
        let x = size.width/2
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x, y: y + 40))
        let dash = SKShapeNode(path: path)
        dash.strokeColor = .white
        dash.lineWidth = 2
        dash.name = "dash"
        addChild(dash)
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard lastUpdate > 0 else { return }
        let dt = currentTime - lastUpdate

        // Move lane markers downward to simulate motion
        let dy = -speedY * CGFloat(dt)
        enumerateChildNodes(withName: "dash") { node, _ in
            node.position.y += dy
            if node.position.y < -40 {
                node.position.y = self.size.height + 40
            }
        }

        // Read inputs
        let dx: CGFloat = 200 // car lateral speed pts/sec
        var moveX: CGFloat = 0
        if side == .left {
            if input?.p1Left == true { moveX -= dx }
            if input?.p1Right == true { moveX += dx }
        } else {
            if input?.p2Left == true { moveX -= dx }
            if input?.p2Right == true { moveX += dx }
        }

        // Apply movement with clamping to track width
        let newX = max(size.width/2 - laneWidth/2,
                       min(size.width/2 + laneWidth/2,
                           car.position.x + moveX * CGFloat(dt)))
        car.position.x = newX
    }

    override func didEvaluateActions() {
        // Ensure lastUpdate is set after scene presented
        if lastUpdate == 0 { lastUpdate = CACurrentMediaTime() }
    }
}
