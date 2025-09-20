import SwiftUI
import SpriteKit

// MARK: - ContentView (thin wrapper to keep the type checker happy)

struct ContentView: View {
    var body: some View {
        GameRootView()
            .navigationBarBackButtonHidden(true)
    }
}

// MARK: - GameRootView (holds state and logic)

private struct GameRootView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var input = PlayerInput()
    @StateObject private var coordinator = GameCoordinator()

    private let sounder = CountdownSounder()

    // UI state
    @State private var pulse = false
    @State private var winnerPulse = false
    @State private var showPause = false
    @State private var confirmHome = false

    // Scenes we control (so we can truly pause & reset)
    @State private var leftScene: GameScene?
    @State private var rightScene: GameScene?
    @State private var lastGeoSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // --- Game area (split into its own view) ---
                GameBoard(leftScene: leftScene, rightScene: rightScene)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .onAppear { onFirstAppear(geo.size) }
                    .onChange(of: geo.size) { newSize in
                        let dx = abs(newSize.width - lastGeoSize.width)
                        let dy = abs(newSize.height - lastGeoSize.height)
                        guard dx > 20 || dy > 20 else { return }
                        createScenes(for: newSize)
                    }

                // Countdown overlay
                CountdownOverlay(startTick: coordinator.startTick,
                                 raceStarted: coordinator.raceStarted,
                                 pulse: $pulse)
                    .allowsHitTesting(false)

                // Winner flash (inline condition—no local let)
                if !coordinator.roundActive && coordinator.raceStarted && !coordinator.showResults {
                    WinnerFlashOverlay(winner: coordinator.winner, winnerPulse: $winnerPulse)
                        .allowsHitTesting(false)
                }

                // Pause buttons (mirrored)
                PauseButtons { showPause = true }
                    .padding(.horizontal, 20)
            }
            // Player 1 controls (bottom)
            .safeAreaInset(edge: .bottom) {
                PlayerControls(title: "PLAYER 1",
                               color: Theme.p1,
                               left: $input.p1Left,
                               right: $input.p1Right)
            }
            // Player 2 controls (top, mirrored)
            .safeAreaInset(edge: .top) {
                PlayerControlsMirrored(title: "PLAYER 2",
                                       color: Theme.p2,
                                       left: $input.p2Left,
                                       right: $input.p2Right)
            }
            // Results sheet (now defined below in this same file)
            .sheet(isPresented: $coordinator.showResults) {
                ResultsSheet(coordinator: coordinator) {
                    pulse = false
                    winnerPulse = false
                    resetRound(playTick3: true, recreateScenes: true)
                }
            }
            // Pause sheet (now defined below)
            .sheet(isPresented: $showPause) {
                PauseSheet(
                    resume: { showPause = false },
                    restart: {
                        showPause = false
                        resetRound(playTick3: true, recreateScenes: true)
                    },
                    goHome: { confirmHome = true }
                )
                .confirmationDialog("Leave the game?", isPresented: $confirmHome, titleVisibility: .visible) {
                    Button("Leave and go to Home", role: .destructive) {
                        showPause = false
                        resumeAll()
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Progress for the current round will be lost.")
                }
            }
            // Countdown sounds
            .onChange(of: coordinator.startTick) { tick in
                // We play the "3" at round start; only blip for 2 and 1 here.
                if tick == 2 || tick == 1 {
                    sounder.playTick(blipLength: 0.18)
                }
            }
            .onChange(of: coordinator.raceStarted) { started in
                if started {
                    sounder.playGoTail(tail: 0.5)
                } else {
                    sounder.stop()
                }
            }
            // Pause/resume tied to sheet & lifecycle (also ducks/unducks BGM)
            .onChange(of: showPause) { presented in
                if presented {
                    pauseAll()
                    BGM.shared.setVolume(0.12, fadeDuration: 0.25)
                } else if !coordinator.showResults {
                    resumeAll()
                    BGM.shared.setVolume(0.20, fadeDuration: 0.25)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active {
                    pauseAll()
                    BGM.shared.setVolume(0.12, fadeDuration: 0.25)
                    showPause = true
                } else if !showPause && !coordinator.showResults {
                    resumeAll()
                    BGM.shared.setVolume(0.20, fadeDuration: 0.25)
                }
            }
        }
    }

    // MARK: - First appear setup (kept out of body to help the type checker)

    private func onFirstAppear(_ size: CGSize) {
        lastGeoSize = size
        if leftScene == nil || rightScene == nil {
            createScenes(for: size)
        }
        resetRound(playTick3: true, recreateScenes: false)
        BGM.shared.play(volume: 0.20)
    }

    // MARK: - Pause/Resume

    private func pauseAll() {
        coordinator.isPaused = true
        leftScene?.isPaused = true
        rightScene?.isPaused = true
    }

    private func resumeAll() {
        coordinator.isPaused = false
        leftScene?.isPaused = false
        rightScene?.isPaused = false
    }

    // MARK: - Reset & Scenes

    private func resetRound(playTick3: Bool, recreateScenes: Bool) {
        resumeAll()
        coordinator.startRound()
        if recreateScenes {
            let size = (lastGeoSize == .zero) ? UIScreen.main.bounds.size : lastGeoSize
            createScenes(for: size)
        }
        if playTick3 {
            // Beep exactly when “3” first appears.
            sounder.playTick(blipLength: 0.18)
        }
    }

    private func createScenes(for size: CGSize) {
        lastGeoSize = size
        leftScene = GameScene(size: CGSize(width: size.width/2, height: size.height),
                              side: .left, input: input, coordinator: coordinator)
        rightScene = GameScene(size: CGSize(width: size.width/2, height: size.height),
                               side: .right, input: input, coordinator: coordinator)
    }
}

// MARK: - Smaller subviews

private struct GameBoard: View {
    let leftScene: SKScene?
    let rightScene: SKScene?

    var body: some View {
        HStack(spacing: 0) {
            SpriteView(scene: leftScene ?? SKScene())
            SpriteView(scene: rightScene ?? SKScene())
        }
    }
}

private struct CountdownOverlay: View {
    let startTick: Int
    let raceStarted: Bool
    @Binding var pulse: Bool

    var body: some View {
        Group {
            if !raceStarted {
                Group {
                    if startTick >= 1 {
                        Text("\(startTick)")
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
            }
        }
        .allowsHitTesting(false)
    }
}

private struct WinnerFlashOverlay: View {
    let winner: Int?
    @Binding var winnerPulse: Bool

    var body: some View {
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
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatCount(2, autoreverses: true)) {
                winnerPulse = true
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PauseButtons: View {
    let tap: () -> Void
    var body: some View {
        VStack {
            Button(action: tap) { PauseChip(label: "Pause").rotationEffect(.degrees(180)) }
                .padding(.top, 6)
                .accessibilityLabel("Pause (top)")
            Spacer()
            Button(action: tap) { PauseChip(label: "Pause") }
                .padding(.bottom, 6)
                .accessibilityLabel("Pause (bottom)")
        }
    }
}

private struct PlayerControls: View {
    var title: String
    var color: Color
    @Binding var left: Bool
    @Binding var right: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).bold().foregroundColor(color)
            HStack(spacing: 12) {
                HoldPad(isPressed: $left,  title: "Left")
                HoldPad(isPressed: $right, title: "Right")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .background(Color.black)
    }
}

private struct PlayerControlsMirrored: View {
    var title: String
    var color: Color
    @Binding var left: Bool
    @Binding var right: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).bold().foregroundColor(color).rotationEffect(.degrees(180))
            HStack(spacing: 12) {
                HoldPad(isPressed: $right, title: "Right", flipText: true)
                HoldPad(isPressed: $left,  title: "Left",  flipText: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .background(Color.black)
    }
}

private struct PauseChip: View {
    var label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pause.fill").font(.subheadline.bold())
            Text(label).font(.subheadline.bold())
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.ultraThinMaterial)
        .foregroundStyle(.white)
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Sheets (defined here so they’re always in scope)

private struct ResultsSheet: View {
    @ObservedObject var coordinator: GameCoordinator
    var playAgain: () -> Void

    var body: some View {
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

            Button("Play Again", action: playAgain)
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

private struct PauseSheet: View {
    var resume: () -> Void
    var restart: () -> Void
    var goHome: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.25))
                .frame(width: 44, height: 5)
                .padding(.top, 6)

            Text("Paused")
                .font(.largeTitle.bold())
                .padding(.top, 4)

            VStack(spacing: 12) {
                Button(action: resume) {
                    BigActionLabel(title: "Resume")
                }
                Button(action: restart) {
                    BigActionLabel(title: "Restart Round")
                }
                Button(role: .destructive, action: goHome) {
                    BigActionLabel(title: "Home", destructive: true)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 6)
        }
        .padding(.bottom, 14)
        .presentationDetents([.height(280), .medium])
    }
}

private struct BigActionLabel: View {
    var title: String
    var destructive: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(destructive ? Color.red.opacity(0.18) : Color.white.opacity(0.10))
            .frame(height: 56)
            .overlay(
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(destructive ? Color.red : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(destructive ? Color.red.opacity(0.35) : Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}
