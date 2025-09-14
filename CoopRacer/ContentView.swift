import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var input = PlayerInput()
    @StateObject private var coordinator = GameCoordinator()

    // Plain helper for countdown ticks
    private let sounder = CountdownSounder()

    @State private var pulse = false
    @State private var winnerPulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ===== Game views (split screen) =====
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

                // ===== Pre-start countdown: 3,2,1, START =====
                if !coordinator.raceStarted {
                    let c = Int(ceil(max(0, coordinator.startCountdown)))
                    Group {
                        if c >= 1 {
                            Text("\(c)")
                                .font(.system(size: 120, weight: .black, design: .rounded))
                        } else {
                            Text("START")
                                .font(.system(size: 96, weight: .black, design: .rounded))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(40)
                    .background(.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .opacity(pulse ? 0.5 : 1.0)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                    .onChange(of: coordinator.startCountdown) { secs in
                        // Play ticks only before the race starts
                        if !coordinator.raceStarted {
                            sounder.maybePlay(for: secs)
                        }
                    }
                }

                // ===== Winner flash (post-round, pre-results) =====
                if !coordinator.roundActive && coordinator.raceStarted && !coordinator.showResults {
                    winnerFlashOverlay(size: geo.size, winner: coordinator.winner)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.5).repeatCount(2, autoreverses: true)) {
                                winnerPulse = true
                            }
                        }
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
                .background(Color.black)
            }
            // ===== Top controls: Player 2 (mirrored text) =====
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
                .background(Color.black)
            }
            // ===== Results sheet =====
            .sheet(isPresented: $coordinator.showResults, onDismiss: {
                pulse = false
                winnerPulse = false
                sounder.reset()
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
                    }
                    .padding(.horizontal, 32)

                    Button("Play Again") {
                        pulse = false
                        winnerPulse = false
                        sounder.reset()
                        coordinator.startRound()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 12)
                }
                .padding(24)
                .presentationDetents([.medium])
            }
            .onAppear {
                sounder.reset()
                coordinator.startRound()
            }
            // Stop any lingering countdown tick right when the race starts
            .onChange(of: coordinator.raceStarted) { started in
                if started { sounder.stop() }
            }
        }
    }

    // Winner flash overlay (soft translucent bars on the winning half)
    private func winnerFlashOverlay(size: CGSize, winner: Int?) -> some View {
        ZStack {
            if winner == 0 {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.p1.opacity(winnerPulse ? 0.25 : 0.4))
                    Rectangle().fill(Theme.p2.opacity(winnerPulse ? 0.25 : 0.4))
                }
            } else {
                HStack(spacing: 0) {
                    Rectangle().fill((winner == 1 ? Theme.p1 : .clear).opacity(winnerPulse ? 0.25 : 0.4))
                    Rectangle().fill((winner == 2 ? Theme.p2 : .clear).opacity(winnerPulse ? 0.25 : 0.4))
                }
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private func makeScene(side: GameScene.Side, size: CGSize) -> SKScene {
        GameScene(size: size, side: side, input: input, coordinator: coordinator)
    }
}
