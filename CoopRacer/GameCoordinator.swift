import Foundation
import Combine

final class GameCoordinator: ObservableObject {

    // MARK: - Published Round State
    @Published var isPaused: Bool = false
    @Published var raceStarted: Bool = false
    @Published var roundActive: Bool = false

    // Countdown (3…2…1…START)
    @Published var startCountdown: Double = 3.0
    @Published var startTick: Int = 3

    // Scores
    @Published var p1Score: Int = 0
    @Published var p2Score: Int = 0

    // Finish Flags
    @Published var p1Finished: Bool = false
    @Published var p2Finished: Bool = false
    @Published var firstFinisher: Int? = nil   // 1 or 2

    // Final Results
    @Published var showResults: Bool = false
    @Published var winner: Int? = nil          // 1 = P1, 2 = P2, 0 = tie (only if simultaneous)

    // Timer used ONLY for countdown, NOT race duration
    private var timer: AnyCancellable?
    private var lastStartTick: Int = 4


    // MARK: - Start Round
    func startRound() {
        // Reset state
        isPaused = false
        p1Score = 0
        p2Score = 0

        p1Finished = false
        p2Finished = false
        firstFinisher = nil

        winner = nil
        showResults = false

        startCountdown = 3.0
        startTick = 3
        lastStartTick = 4

        raceStarted = false
        roundActive  = false

        timer?.cancel()

        // Countdown timer only
        timer = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isPaused { return }

                // === Countdown Phase ===
                if !self.raceStarted {
                    self.startCountdown -= 0.016

                    let tick = max(0, Int(ceil(self.startCountdown)))
                    if tick != self.lastStartTick {
                        self.lastStartTick = tick
                        self.startTick = tick
                    }

                    if self.startCountdown <= 0 {
                        self.startCountdown = 0
                        self.raceStarted = true
                        self.roundActive = true
                    }

                    return
                }

                // After countdown, stop timer — scene now drives the race
                self.timer?.cancel()
            }
    }


    // MARK: - Player Finishes Track
    func markFinished(player: Int) {
        if player == 1 {
            if !p1Finished { p1Finished = true }
            if firstFinisher == nil { firstFinisher = 1 }
        } else {
            if !p2Finished { p2Finished = true }
            if firstFinisher == nil { firstFinisher = 2 }
        }

        tryCompleteRound()
    }


    // MARK: - Completion Check
    private func tryCompleteRound() {
        guard p1Finished && p2Finished else { return }

        // Round ends
        roundActive = false
        raceStarted = false

        // Determine winner
        if let first = firstFinisher {
            winner = first
        } else {
            winner = 0   // simultaneous or fallback
        }

        // Progress unlocks
        SettingsStore.shared.registerRoundResult(winner: winner)

        // Small delay for UI celebration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showResults = true
        }
    }


    // MARK: - Score Increment
    func addScore(player1: Bool, points: Int) {
        if player1 { p1Score += points } else { p2Score += points }
    }


    // MARK: - Manual Stop (if needed)
    func endRound() {
        roundActive = false
        raceStarted = false

        // Winner still respects "first to finish"
        if let first = firstFinisher {
            winner = first
        } else {
            // fallback: use score if someone forced end
            if p1Score > p2Score { winner = 1 }
            else if p2Score > p1Score { winner = 2 }
            else { winner = 0 }
        }

        SettingsStore.shared.registerRoundResult(winner: winner)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.showResults = true
        }
    }
}
