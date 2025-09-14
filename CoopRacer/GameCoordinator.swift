import Foundation
import Combine

final class GameCoordinator: ObservableObject {
    // Global pause (freezes countdown and round timer)
    @Published var isPaused: Bool = false

    // Round state
    @Published var roundActive: Bool = false        // running 30s timer
    @Published var raceStarted: Bool = false        // flips true at "START"

    // Pre-start countdown
    @Published var startCountdown: Double = 3.0     // 3…0 for internal use
    @Published var startTick: Int = 3               // emits 3,2,1,0 (discrete for UI/sound)

    // Round timer & scoring
    @Published var timeRemaining: Double = 30.0
    @Published var p1Score: Int = 0
    @Published var p2Score: Int = 0

    // Results
    @Published var showResults: Bool = false
    @Published var winner: Int? = nil               // 1 = P1, 2 = P2, 0 = tie

    private var timer: AnyCancellable?
    private var lastStartTick: Int = 4              // forces first emission to be 3

    func startRound() {
        isPaused = false
        p1Score = 0
        p2Score = 0
        timeRemaining = 30
        roundActive = false
        raceStarted = false

        startCountdown = 3.0
        startTick = 3
        lastStartTick = 4

        showResults = false
        winner = nil

        timer?.cancel()
        timer = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                // Global pause: freeze clocks
                if self.isPaused { return }

                // Phase 1 — pre-start countdown
                if !self.raceStarted {
                    self.startCountdown -= 0.016

                    let tickNow = max(0, Int(ceil(self.startCountdown))) // 3,2,1,0
                    if tickNow != self.lastStartTick {
                        self.lastStartTick = tickNow
                        self.startTick = tickNow
                    }

                    if self.startCountdown <= 0 {
                        self.startCountdown = 0
                        self.raceStarted = true
                        self.roundActive = true
                    }
                    return
                }

                // Phase 2 — round running
                guard self.roundActive else { return }
                self.timeRemaining -= 0.016
                if self.timeRemaining <= 0 {
                    self.timeRemaining = 0
                    self.roundActive = false

                    // Decide winner
                    if self.p1Score > self.p2Score { self.winner = 1 }
                    else if self.p2Score > self.p1Score { self.winner = 2 }
                    else { self.winner = 0 }

                    self.timer?.cancel()
                    // Give UI time to flash winner, then show results
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if !self.roundActive && self.raceStarted { self.showResults = true }
                    }
                }
            }
    }

    func endRound() {
        isPaused = false
        roundActive = false
        raceStarted = false
        if p1Score > p2Score { winner = 1 }
        else if p2Score > p1Score { winner = 2 }
        else { winner = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.showResults = true
        }
    }

    func addScore(player1: Bool, points: Int) {
        if player1 { p1Score += points } else { p2Score += points }
    }
}
