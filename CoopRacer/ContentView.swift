import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var input = PlayerInput()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Two racing views side-by-side
                HStack(spacing: 0) {
                    SpriteView(scene: makeScene(side: .left,
                                                size: CGSize(width: geo.size.width/2,
                                                             height: geo.size.height)))
                    SpriteView(scene: makeScene(side: .right,
                                                size: CGSize(width: geo.size.width/2,
                                                             height: geo.size.height)))
                }
                .background(Color.black)
                .ignoresSafeArea()
            }
            // Player 1 controls – BOTTOM edge
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Text("PLAYER 1")
                        .font(.caption).bold()
                        .foregroundColor(Theme.p1.opacity(0.9))
                    HStack(spacing: 12) {
                        HoldPad(isPressed: $input.p1Left,  title: "Left")
                        HoldPad(isPressed: $input.p1Right, title: "Right")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                .background(Theme.p1.opacity(0.10).blendMode(.plusLighter))
            }

            // Player 2 controls – TOP edge (flip only the text for readability)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    Text("PLAYER 2")
                        .font(.caption).bold()
                        .foregroundColor(Theme.p2.opacity(0.9))
                        .rotationEffect(.degrees(180)) // label readable for top player
                    HStack(spacing: 12) {
                        // Text flips only; inputs stay as booleans
                        HoldPad(isPressed: $input.p2Right, title: "Right", flipText: true)
                        HoldPad(isPressed: $input.p2Left,  title: "Left",  flipText: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .background(Theme.p2.opacity(0.10).blendMode(.plusLighter))
            }
        }
    }

    private func makeScene(side: GameScene.Side, size: CGSize) -> SKScene {
        let scene = GameScene(size: size, side: side, input: input)
        scene.scaleMode = .resizeFill
        return scene
    }
}
