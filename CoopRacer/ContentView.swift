import SwiftUI
import SpriteKit

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var settings: SettingsStore

    @StateObject private var input = PlayerInput()
    @StateObject private var coordinator = GameCoordinator()

    private let sounder = CountdownSounder()

    // UI state
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

    var body: some View {
        GeometryReader { geo in
            content(geo: geo)
        }
        .background(AdPresenter()) // invisible presenter VC for interstitials
        .navigationBarBackButtonHidden(true)

        // Keep BGM + game state in sync with interstitials
       
        .onReceive(NotificationCenter.default.publisher(for: .adWillPresent)) { _ in
            pauseAll()
            BGM.shared.setVolume(0.0, fadeDuration: 0.15)   // <- hard mute
        }

        .onReceive(NotificationCenter.default.publisher(for: .adDidDismiss)) { _ in
            if !coordinator.showResults && !showPause { resumeAll() }
            BGM.shared.setVolume(0.20, fadeDuration: 0.20)  // <- restore
            AdManager.shared.preload()
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
            // Attempt interstitial only once after the sheet is fully gone
            if !didTryAdAfterResults {
                didTryAdAfterResults = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    AdManager.shared.presentIfAllowed()
                }
            }
        }) {
            ResultsSheet(coordinator: coordinator) {
                pulse = false
                winnerPulse = false
                resetRound(playTick3: true, recreateScenes: true)
            }
            .onAppear {
                AdManager.shared.noteRoundCompleted()
                AdManager.shared.preload()
                didTryAdAfterResults = false
                // ✅ Save high score using the new store
                let p1 = SettingsStore.shared.player1Name
                let p2 = SettingsStore.shared.player2Name
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
                    resetRound(playTick3: true, recreateScenes: true)
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
            if tick == 3 || tick == 2 || tick == 1 {
                sounder.playTick(blipLength: 0.18)
            }
        }
        .onChange(of: coordinator.raceStarted) { started in
            if started {
                // (Box-car GameScene has no engine hooks; we just do the GO tail.)
                sounder.playGoTail(tail: 0.5)
            } else {
                sounder.stop()
            }
        }
        // Pause/resume tied to sheet & lifecycle
        .onChange(of: showPause) { presented in
            if presented {
                pauseAll(); BGM.shared.setVolume(0.12, fadeDuration: 0.25)
            } else if !coordinator.showResults {
                resumeAll(); BGM.shared.setVolume(0.20, fadeDuration: 0.25)
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
                BGM.shared.play(volume: 0.20)
            }
            .onChange(of: geo.size) { newSize in
                // Rebuild scenes only on meaningful size changes
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
        resumeAll()
        coordinator.startRound()
        if recreateScenes {
            let size = (lastGeoSize == .zero) ? UIScreen.main.bounds.size : lastGeoSize
            createScenes(for: size)
        }
        if playTick3 {
            sounder.playTick(blipLength: 0.18)
        }
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

// MARK: - Small reusable views

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

// MARK: - Sheets (bundled so you won’t get “not in scope”)

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
        NavigationStack {
            List {
                Section {
                    Button("Resume", action: resume)
                    Button("Restart Round", action: restart)
                    Button("Leave and go to Home", role: .destructive, action: goHome)
                }
            }
            .navigationTitle("Paused")
        }
        .presentationDetents([.medium])
    }
}
