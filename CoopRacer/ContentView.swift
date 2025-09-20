import SwiftUI
import SpriteKit

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var input = PlayerInput()
    @StateObject private var coordinator = GameCoordinator()

    private let sounder = CountdownSounder()

    // UI state
    @State private var pulse = false
    @State private var winnerPulse = false
    @State private var showPause = false
    @State private var confirmHome = false   // legacy, no longer used inside sheet
    @State private var askHome = false       // root-level confirm dialog

    // Scenes we control (so we can truly pause & reset)
    @State private var leftScene: GameScene?
    @State private var rightScene: GameScene?
    @State private var lastGeoSize: CGSize = .zero

    // Ad + navigation coordination
    @State private var adShowing = false
    @State private var pendingRestart = false
    @State private var navigatingHome = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GameBoard(leftScene: leftScene, rightScene: rightScene)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .onAppear {
                        lastGeoSize = geo.size
                        if leftScene == nil || rightScene == nil {
                            createScenes(for: geo.size)
                        }
                        // Prime audio and start a fresh round + play the "3" tick
                        startRoundNow()
                        // Background music for race screen
                        BGM.shared.play(volume: 0.20)
                    }
                    // iOS 17 onChange (two-parameter: old, new)
                    .onChange(of: geo.size) { _, newSize in
                        // Rebuild scenes only on meaningful size changes (avoid sheet jitter)
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

                // Winner flash
                let showWinner = (!coordinator.roundActive && coordinator.raceStarted && !coordinator.showResults)
                if showWinner {
                    WinnerFlashOverlay(winner: coordinator.winner, winnerPulse: $winnerPulse)
                        .allowsHitTesting(false)
                }

                // Pause buttons
                PauseButtons { showPause = true }
                    .padding(.horizontal, 20)
            }
            // Stable UIKit presenter for ads
            .background(AdPresenter())

            // Listen for ad show/hide -> pause/resume cleanly
            .onReceive(NotificationCenter.default.publisher(for: .adWillPresent)) { _ in
                adShowing = true
                pauseAll()
                BGM.shared.pause(fade: 0.25)   // ✅ fully pause the music
            }

            .onReceive(NotificationCenter.default.publisher(for: .adDidDismiss)) { _ in
                adShowing = false

                if pendingRestart {
                    startRoundNow()
                    pendingRestart = false
                } else if !showPause && !coordinator.showResults {
                    resumeAll()
                }
                BGM.shared.resume(fade: 0.25, to: 0.20)   // ✅ resume at your normal level
            }

            // Results sheet
            .sheet(isPresented: $coordinator.showResults, onDismiss: {
                AdManager.shared.presentIfAllowed { shown in
                    if shown {
                        pendingRestart = true
                    } else {
                        startRoundNow()
                    }
                }
            }) {
                ResultsSheet(coordinator: coordinator) {
                    coordinator.showResults = false
                }
            }

            // Pause sheet
            .sheet(isPresented: $showPause) {
                PauseSheet(
                    resume: { showPause = false },
                    restart: {
                        showPause = false
                        startRoundNow()
                    },
                    requestHome: {
                        // Dismiss pause first, then show confirm dialog at root
                        showPause = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            askHome = true
                        }
                    }
                )
            }

            // Root-level confirmation dialog
            .confirmationDialog("Leave the game?",
                                isPresented: $askHome,
                                titleVisibility: .visible) {
                Button("Leave and go to Home", role: .destructive) {
                    navigatingHome = true
                    resumeAll()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Progress for the current round will be lost.")
            }

            // Countdown sounds
            .onChange(of: coordinator.startTick) { _, tick in
                if tick == 2 || tick == 1 {
                    if !adShowing {
                        sounder.playTick(blipLength: 0.18)
                    }
                }
            }
            // iOS 17 zero-parameter form: just react to the change and read current value
            .onChange(of: coordinator.raceStarted) {
                if coordinator.raceStarted {
                    leftScene?.onRaceStarted()
                    rightScene?.onRaceStarted()
                    sounder.playGoTail(tail: 0.5)
                } else {
                    leftScene?.onRaceEnded()
                    rightScene?.onRaceEnded()
                    sounder.stop()
                }
            }

            // Pause/resume tied to sheet (two-parameter)
            .onChange(of: showPause) { _, presented in
                if presented {
                    pauseAll()
                    BGM.shared.setVolume(0.12, fadeDuration: 0.25)
                } else if !coordinator.showResults && !adShowing {
                    resumeAll()
                    BGM.shared.setVolume(0.20, fadeDuration: 0.25)
                }
            }

            // Lifecycle: avoid auto-pause during ads or home nav (two-parameter)
            .onChange(of: scenePhase) { _, phase in
                if adShowing || navigatingHome { return }
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
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            navigatingHome = false
        }
        // Bottom controls (P1)
        .safeAreaInset(edge: .bottom) {
            PlayerControls(title: "PLAYER 1",
                           color: Theme.p1,
                           left: $input.p1Left,
                           right: $input.p1Right)
        }
        // Top controls (P2 mirrored)
        .safeAreaInset(edge: .top) {
            PlayerControlsMirrored(title: "PLAYER 2",
                                   color: Theme.p2,
                                   left: $input.p2Left,
                                   right: $input.p2Right)
        }
    }

    // MARK: - Helpers

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

    private func startRoundNow() {
        pulse = false
        winnerPulse = false
        resumeAll()
        coordinator.startRound()
        sounder.playTick(blipLength: 0.18) // the "3"
        if leftScene == nil || rightScene == nil {
            let size = (lastGeoSize == .zero) ? UIScreen.main.bounds.size : lastGeoSize
            createScenes(for: size)
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

// MARK: - Subviews

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
    }
}

private struct PauseButtons: View {
    let tap: () -> Void
    var body: some View {
        VStack {
            Button(action: tap) { PauseChip(label: "Pause").rotationEffect(.degrees(180)) }
                .padding(.top, 6)
            Spacer()
            Button(action: tap) { PauseChip(label: "Pause") }
                .padding(.bottom, 6)
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
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
    }
}

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
            Button("Play Again") { playAgain() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
        }
        .padding(24)
        .presentationDetents([.medium])
        .onAppear {
            AdManager.shared.noteRoundCompleted()
            AdManager.shared.preload()
        }
    }
}

private struct PauseSheet: View {
    var resume: () -> Void
    var restart: () -> Void
    var requestHome: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Paused").font(.title).bold().padding(.top, 8)
            Button("Resume", action: resume).buttonStyle(.borderedProminent)
            Button("Restart Round", action: restart).buttonStyle(.bordered)
            Button("Leave and go Home", role: .destructive, action: requestHome).buttonStyle(.bordered)
            Spacer(minLength: 8)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
