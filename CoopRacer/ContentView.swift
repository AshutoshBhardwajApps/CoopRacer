import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var input = PlayerInput()
    @StateObject private var coordinator = GameCoordinator()

    // Countdown flashing animation
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Two racing views side-by-side (no road under bars because bars are solid black)
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

                // ===== Countdown overlay (soft, translucent) =====
                if coordinator.roundActive && coordinator.timeRemaining <= 5.0 {
                    let count = max(1, Int(ceil(coordinator.timeRemaining)))
                    Text("\(count)")
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(40)
                        .background(.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .opacity(pulse ? 0.5 : 1.0)
                        .scaleEffect(pulse ? 1.1 : 0.95)
                        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulse = true
                        }}
                }
            }
            // ===== Bottom controls: Player 1 =====
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Text("PLAYER 1").font(.caption).bold().foregroundColor(Theme.p1)
                    HStack(spacing: 12) {
                        HoldPad(isPressed: $input.p1Left,  title: "Left")
                        HoldPad(isPressed: $input.p1Right, title: "Right")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                .background(Color.black)          // solid black so road is not visible behind
            }
            // ===== Top controls: Player 2 =====
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    Text("PLAYER 2")
                        .font(.caption).bold().foregroundColor(Theme.p2)
                        .rotationEffect(.degrees(180))
                    HStack(spacing: 12) {
                        HoldPad(isPressed: $input.p2Right, title: "Right", flipText: true)
                        HoldPad(isPressed: $input.p2Left,  title: "Left",  flipText: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .background(Color.black)          // solid black
            }
            // ===== Results =====
            .sheet(isPresented: $coordinator.showResults, onDismiss: {
                coordinator.startRound()
            }) {
                VStack(spacing: 20) {
                    Text("Round Over").font(.largeTitle).bold()
                    HStack {
                        VStack {
                            Text("Player 1").foregroundStyle(Theme.p1).bold()
                            Text("\(coordinator.p1Score)").font(.title)
                        }
                        Spacer()
                        VStack {
                            Text("Player 2").foregroundStyle(Theme.p2).bold()
                            Text("\(coordinator.p2Score)").font(.title)
                        }
                    }.padding(.horizontal, 32)
                    Button("Play Again") {
                        coordinator.startRound()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 12)
                }
                .padding(24)
                .presentationDetents([.medium])
            }
            .onAppear { coordinator.startRound() }
        }
    }

    private func makeScene(side: GameScene.Side, size: CGSize) -> SKScene {
        GameScene(size: size, side: side, input: input, coordinator: coordinator)
    }
}
