//
//  SoloGameView.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-11-22.
//

import SwiftUI
import SpriteKit

struct SoloGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var settings: SettingsStore

    // SOLO coordinator
    @StateObject private var input       = PlayerInput()
    @StateObject private var coordinator = GameCoordinator(mode: .solo)

    private let sounder = CountdownSounder()

    // UI state
    @State private var pulse       = false
    @State private var showPause   = false
    @State private var confirmHome = false

    // Ad coordination
    @State private var didTryAdAfterResults = false
    @State private var goHomeAfterResults   = false

    // Scene
    @State private var scene: GameScene?
    @State private var lastGeoSize: CGSize = .zero

    // Convenience
    private var adsDisabled: Bool {
        settings.hasRemovedAds
    }

    var body: some View {
        GeometryReader { geo in
            content(geo: geo)
        }
        .navigationBarBackButtonHidden(true)

        // 🔊 Keep solo mode in sync with interstitial ads
        .onReceive(NotificationCenter.default.publisher(for: .adWillPresent)) { _ in
            pauseAll()
            BGM.shared.setVolume(0.0, fadeDuration: 0.15)
        }
        .onReceive(NotificationCenter.default.publisher(for: .adDidDismiss)) { _ in
            // Only resume if SoloGameView is still active and no sheets are up
            if scene != nil && !coordinator.showResults && !showPause {
                resumeAll()
            }

            if settings.musicEnabled {
                BGM.shared.setVolume(0.20, fadeDuration: 0.20)
            } else {
                BGM.shared.stop()
            }

            if !adsDisabled {
                AdManager.shared.preload()
            }
        }

        // Clear flags when returning Home
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CoopRacer.ResetNavFlag"))) { _ in
            showPause = false
            confirmHome = false
            didTryAdAfterResults = false
            goHomeAfterResults = false
        }

        // ⚠️ No heavy cleanup in onDisappear — avoids killing scene when ads/sheets appear
    }

    // MARK: - Split body

    @ViewBuilder
    private func content(geo: GeometryProxy) -> some View {
        ZStack {
            SoloGameArea(
                scene: scene,
                geo: geo,
                lastGeoSize: $lastGeoSize,
                settings: settings,
                createScene: createScene,
                resetRound: resetRound
            )

            CountdownOverlay(
                startTick: coordinator.startTick,
                raceStarted: coordinator.raceStarted,
                pulse: $pulse
            )
            .allowsHitTesting(false)
        }
        // Bottom controls – single player only
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                // Single pause button for Player 1 (bottom area)
                HStack {
                    Spacer()
                    Button {
                        showPause = true
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.p1)
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 24)
                }

                // Player 1 controls
                PlayerControls(
                    title: settings.player1Name.uppercased(),
                    color: Theme.p1,
                    left: $input.p1Left,
                    right: $input.p1Right
                )
            }
        }
        // Results sheet
        .sheet(isPresented: $coordinator.showResults, onDismiss: {
            // After the sheet closes, try to show an interstitial
            if !adsDisabled && !didTryAdAfterResults {
                didTryAdAfterResults = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    AdManager.shared.presentIfAllowed()
                }
            }

            // If user chose "Go Home", navigate after giving the ad a chance
            if goHomeAfterResults {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    goHomeAfterResults = false
                    dismiss()
                }
            }
        }) {
            SoloResultsSheet(
                playerName: settings.player1Name,
                score: coordinator.p1Score,
                playAgain: {
                    // Close sheet, then reset round shortly after
                    coordinator.showResults = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        resetRound(playTick3: true, recreateScene: false)
                    }
                },
                goHome: {
                    // Mark that we want to go home; onDismiss handles nav
                    goHomeAfterResults = true
                    coordinator.showResults = false
                }
            )
            .onAppear {
                // Save SOLO high score
                SoloHighScoresStore.shared.add(
                    playerName: settings.player1Name,
                    score: coordinator.p1Score,
                    speedLevel: settings.selectedSpeedLevel
                )

                // Track & preload ads for this completed run (if ads enabled)
                if !adsDisabled {
                    AdManager.shared.noteRoundCompleted()
                    AdManager.shared.preload()
                    didTryAdAfterResults = false
                }
            }
        }
        // Pause sheet
        .sheet(isPresented: $showPause) {
            PauseSheet(
                resume: { showPause = false },
                restart: {
                    showPause = false
                    resetRound(playTick3: true, recreateScene: false)
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
                sounder.playTick(blipLength: 0.18)
            }
        }
        .onChange(of: coordinator.raceStarted) { started in
            if started {
                sounder.playGoTail(tail: 0.5)

                // immediately mute then fade in BGM
                BGM.shared.setVolume(0.0, fadeDuration: 0.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    BGM.shared.setVolume(0.20, fadeDuration: 0.8)
                }
            } else {
                sounder.stop()
            }
        }
        // 🔐 SOLO SAFETY: if P1 is marked finished, force-end the round
        // This guarantees showResults + ads even if solo-mode completion
        // logic misfires for any reason.
        .onChange(of: coordinator.p1Finished) { finished in
            if finished && !coordinator.showResults {
                coordinator.endRound()
            }
        }
        // Pause/resume on sheet
        .onChange(of: showPause) { presented in
            if presented {
                pauseAll()
                BGM.shared.setVolume(0.12, fadeDuration: 0.25)
            } else if !coordinator.showResults {
                resumeAll()
                BGM.shared.setVolume(0.20, fadeDuration: 0.25)
            }
        }
        // Pause on app background
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

    // MARK: - Pause/Resume

    private func pauseAll() {
        coordinator.isPaused = true
        scene?.isPaused = true
    }

    private func resumeAll() {
        coordinator.isPaused = false
        scene?.isPaused = false
    }

    // MARK: - Reset & Scene

    private func resetRound(playTick3: Bool, recreateScene: Bool) {
        sounder.stop()
        coordinator.startRound()

        if recreateScene {
            let size = (lastGeoSize == .zero) ? UIScreen.main.bounds.size : lastGeoSize
            createScene(for: size)
        }

        resumeAll()

        DispatchQueue.main.async {
            self.scene?.prepareForNewRound()
        }

        BGM.shared.setVolume(0.0, fadeDuration: 0.0)

        if playTick3 {
            sounder.playTick(blipLength: 0.18)
        }
    }

    private func createScene(for size: CGSize) {
        lastGeoSize = size
        scene = GameScene(
            size: size,
            side: .left,               // solo lane
            input: input,
            coordinator: coordinator,
            carPNG: settings.player1Car,
            mode: .solo                // visual/behavioural solo mode
        )
    }
}

// MARK: - Simple board area moved to its own struct

private struct SoloGameArea: View {
    let scene: SKScene?
    let geo: GeometryProxy
    @Binding var lastGeoSize: CGSize

    let settings: SettingsStore
    let createScene: (CGSize) -> Void
    let resetRound: (_ playTick3: Bool, _ recreateScene: Bool) -> Void

    var body: some View {
        SpriteView(scene: scene ?? SKScene())
            .background(Color.black)
            .ignoresSafeArea()
            .onAppear {
                lastGeoSize = geo.size
                if scene == nil {
                    createScene(geo.size)
                }
                resetRound(true, false)

                // Start BGM at 0 for countdown
                BGM.shared.play(volume: 0.0)
            }
            .onChange(of: geo.size) { newSize in
                let dx = abs(newSize.width  - lastGeoSize.width)
                let dy = abs(newSize.height - lastGeoSize.height)
                guard dx > 20 || dy > 20 else { return }
                createScene(newSize)
            }
    }
}

// MARK: - Solo Results sheet

private struct SoloResultsSheet: View {
    let playerName: String
    let score: Int
    let playAgain: () -> Void
    let goHome: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Run Complete")
                .font(.largeTitle).bold()

            VStack(spacing: 8) {
                Text(playerName)
                    .foregroundStyle(Theme.p1)
                    .font(.headline).bold()
                Text("Score: \(score)")
                    .font(.title.monospacedDigit())
            }

            HStack(spacing: 12) {
                Button("Play Again", action: playAgain)
                    .buttonStyle(.borderedProminent)

                Button("Go Home", role: .destructive, action: goHome)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .presentationDetents([ .medium ])
    }
}
