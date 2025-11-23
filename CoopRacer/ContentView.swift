import SwiftUI
import SpriteKit

// MARK: - ContentView (Two-Player Mode)

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var settings: SettingsStore

    @StateObject private var input = PlayerInput()
    @StateObject private var coordinator = GameCoordinator()

    private let sounder = CountdownSounder()

    // UI state
    @State private var goHomeAfterResults = false
    @State private var pulse = false
    @State private var winnerPulse = false
    @State private var showPause = false
    @State private var confirmHome = false

    // Scenes
    @State private var leftScene: GameScene?
    @State private var rightScene: GameScene?
    @State private var lastGeoSize: CGSize = .zero

    // Ad coordination
    @State private var didTryAdAfterResults = false

    // Convenience
    private var adsDisabled: Bool {
        settings.hasRemovedAds
    }

    var body: some View {
        GeometryReader { geo in
            content(geo: geo)
        }
        .background(AdPresenter()) // invisible presenter VC for interstitials
        .navigationBarBackButtonHidden(true)

        // Keep BGM + game state in sync with interstitials
        .onReceive(NotificationCenter.default.publisher(for: .adWillPresent)) { _ in
            pauseAll()
            BGM.shared.setVolume(0.0, fadeDuration: 0.15)   // hard mute
        }
        .onReceive(NotificationCenter.default.publisher(for: .adDidDismiss)) { _ in
            if !coordinator.showResults && !showPause {
                resumeAll()
            }
            BGM.shared.setVolume(0.20, fadeDuration: 0.20)  // restore

            if !adsDisabled {
                AdManager.shared.preload()
            }
        }

        // Clear any lingering flags when HomeView appears
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CoopRacer.ResetNavFlag"))) { _ in
            showPause = false
            confirmHome = false
            didTryAdAfterResults = false
        }
    }

    // MARK: - Split body (keeps the compiler happy)

    @ViewBuilder
    private func content(geo: GeometryProxy) -> some View {
        ZStack {
            GameArea(geo: geo)

            CountdownOverlay(startTick: coordinator.startTick,
                             raceStarted: coordinator.raceStarted,
                             pulse: $pulse)
                .allowsHitTesting(false)

            WinnerLayer(coordinator: coordinator, winnerPulse: $winnerPulse)
                .allowsHitTesting(false)

            PauseButtons { showPause = true }
                .padding(.horizontal, 20)
        }
        // Player 1 controls (bottom)
        .safeAreaInset(edge: .bottom) {
            PlayerControls(title: settings.player1Name.uppercased(),
                           color: Theme.p1,
                           left: $input.p1Left,
                           right: $input.p1Right)
        }
        // Player 2 controls (top, mirrored)
        .safeAreaInset(edge: .top) {
            PlayerControlsMirrored(title: settings.player2Name.uppercased(),
                                   color: Theme.p2,
                                   left: $input.p2Left,
                                   right: $input.p2Right)
        }
        // Results sheet
        .sheet(isPresented: $coordinator.showResults, onDismiss: {
            if !adsDisabled && !didTryAdAfterResults {
                didTryAdAfterResults = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    AdManager.shared.presentIfAllowed()
                }
            }

            if goHomeAfterResults {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    goHomeAfterResults = false
                    dismiss()
                }
            }
        }) {
            ResultsSheet(coordinator: coordinator) {
                // PLAY AGAIN
                pulse = false
                winnerPulse = false
                coordinator.showResults = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    resetRound(playTick3: true, recreateScenes: false)
                }

            } goHome: {
                // GO HOME
                goHomeAfterResults = true
                coordinator.showResults = false
            }
            .environmentObject(settings)
            .onAppear {
                if !adsDisabled {
                    AdManager.shared.noteRoundCompleted()
                    AdManager.shared.preload()
                    didTryAdAfterResults = false
                }

                HighScoresStore.shared.add(
                    p1Name: SettingsStore.shared.player1Name,
                    p2Name: SettingsStore.shared.player2Name,
                    p1Score: coordinator.p1Score,
                    p2Score: coordinator.p2Score
                )
            }
        }
        // Pause sheet
        .sheet(isPresented: $showPause) {
            PauseSheet(
                resume: { showPause = false },
                restart: {
                    showPause = false
                    resetRound(playTick3: true, recreateScenes: false)
                },
                goHome: { confirmHome = true }
            )
            .confirmationDialog("Leave the game?",
                                isPresented: $confirmHome,
                                titleVisibility: .visible) {
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
            if tick == 3 {
                BGM.shared.setVolume(0.0, fadeDuration: 0.10)
            }

            if tick == 3 || tick == 2 || tick == 1 {
                if settings.effectsEnabled {
                    sounder.playTick(blipLength: 0.18)
                }
            }
        }
        .onChange(of: coordinator.raceStarted) { started in
            if started {
                if settings.effectsEnabled {
                    sounder.playGoTail(tail: 0.5)
                }

                if settings.musicEnabled {
                    BGM.shared.play(volume: 0.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        BGM.shared.setVolume(0.20, fadeDuration: 0.8)
                    }
                } else {
                    BGM.shared.stop()
                }
            } else {
                sounder.stop()
            }
        }
        // Pause/resume tied to sheet & lifecycle
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

    // MARK: - Sub-blocks

    @ViewBuilder
    private func GameArea(geo: GeometryProxy) -> some View {
        GameBoard(leftScene: leftScene, rightScene: rightScene)
            .background(Color.black)
            .ignoresSafeArea()
            .onAppear {
                lastGeoSize = geo.size
                if leftScene == nil || rightScene == nil {
                    createScenes(for: geo.size)
                }
                resetRound(playTick3: true, recreateScenes: false)

                if settings.musicEnabled {
                    BGM.shared.play(volume: 0.0)
                } else {
                    BGM.shared.stop()
                }
            }
            .onChange(of: geo.size) { newSize in
                let dx = abs(newSize.width - lastGeoSize.width)
                let dy = abs(newSize.height - lastGeoSize.height)
                guard dx > 20 || dy > 20 else { return }
                createScenes(for: newSize)
            }
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
        sounder.stop()
        coordinator.startRound()

        if recreateScenes {
            let size = (lastGeoSize == .zero) ? UIScreen.main.bounds.size : lastGeoSize
            createScenes(for: size)
        }

        resumeAll()

        DispatchQueue.main.async {
            self.leftScene?.prepareForNewRound()
            self.rightScene?.prepareForNewRound()
        }

        BGM.shared.setVolume(0.0, fadeDuration: 0.0)
        // SFX for 3-2-1 now handled by startTick changes
    }

    private func createScenes(for size: CGSize) {
        lastGeoSize = size
        let half = CGSize(width: size.width / 2, height: size.height)
        leftScene  = GameScene(size: half,
                               side: .left,
                               input: input,
                               coordinator: coordinator,
                               carPNG: settings.player1Car)

        rightScene = GameScene(size: half,
                               side: .right,
                               input: input,
                               coordinator: coordinator,
                               carPNG: settings.player2Car)
    }
}

// MARK: - Small reusable views that are *only* for 2-player layout

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

private struct WinnerLayer: View {
    @ObservedObject var coordinator: GameCoordinator
    @Binding var winnerPulse: Bool

    var body: some View {
        let winner = coordinator.winner
        let show = (!coordinator.roundActive && coordinator.raceStarted && !coordinator.showResults)

        return Group {
            if show {
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
    }
}

// Still private – only used by 2-player mode
private struct ResultsSheet: View {
    @ObservedObject var coordinator: GameCoordinator
    @EnvironmentObject var settings: SettingsStore
    var playAgain: () -> Void
    var goHome: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Round Over").font(.largeTitle).bold()

            HStack {
                VStack {
                    Text(settings.player1Name)
                        .foregroundStyle(Theme.p1)
                        .font(.headline).bold()
                    Text("\(coordinator.p1Score)")
                        .font(.title.monospacedDigit())
                }
                Spacer()
                VStack {
                    Text(settings.player2Name)
                        .foregroundStyle(Theme.p2)
                        .font(.headline).bold()
                    Text("\(coordinator.p2Score)")
                        .font(.title.monospacedDigit())
                }
            }
            .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Play Again", action: playAgain)
                    .buttonStyle(.borderedProminent)

                Button("Go Home", role: .destructive, action: goHome)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
