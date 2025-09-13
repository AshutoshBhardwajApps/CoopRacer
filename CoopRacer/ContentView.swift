
import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var input = PlayerInput()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Center: two racing views side-by-side
                HStack(spacing: 0) {
                    SpriteView(scene: makeScene(side: .left, size: CGSize(width: geo.size.width/2, height: geo.size.height - 140)))
                        .ignoresSafeArea()
                    SpriteView(scene: makeScene(side: .right, size: CGSize(width: geo.size.width/2, height: geo.size.height - 140)))
                        .ignoresSafeArea()
                }
                .frame(width: geo.size.width, height: geo.size.height - 140, alignment: .center)
                .position(x: geo.size.width/2, y: geo.size.height/2)

                // Bottom controls: Player 1
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { input.p1Left = true }) {
                            Text("Left").frame(maxWidth: .infinity).padding()
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in input.p1Left = false })
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in input.p1Left = isPressing }) {}

                        Button(action: { input.p1Right = true }) {
                            Text("Right").frame(maxWidth: .infinity).padding()
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in input.p1Right = false })
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in input.p1Right = isPressing }) {}
                    }
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(height: 70)
                    .background(Color.red.opacity(0.08))
                }

                // Top controls: Player 2 (rotated 180° so it's upright for the top player)
                VStack {
                    HStack {
                        Button(action: { input.p2Right = true }) {
                            Text("Right").frame(maxWidth: .infinity).padding()
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in input.p2Right = false })
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in input.p2Right = isPressing }) {}

                        Button(action: { input.p2Left = true }) {
                            Text("Left").frame(maxWidth: .infinity).padding()
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in input.p2Left = false })
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in input.p2Left = isPressing }) {}
                    }
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .frame(height: 70)
                    .background(Color.blue.opacity(0.08))
                    Spacer()
                }
                .rotationEffect(.degrees(180)) // flips for the top player
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
        }
    }

    private func makeScene(side: GameScene.Side, size: CGSize) -> SKScene {
        let scene = GameScene(size: size, side: side, input: input)
        scene.scaleMode = .resizeFill
        return scene
    }
}
