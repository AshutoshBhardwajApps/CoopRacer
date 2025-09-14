import Foundation
import Combine

final class GameCoordinator: ObservableObject {
    @Published var roundActive: Bool = false        // running 30s timer
    @Published var raceStarted: Bool = false        // flips to true at "START"
    @Published var startCountdown: Double = 3.0     // 3..0 (then "START")

    @Published var timeRemaining: Double = 30.0
    @Published var p1Score: Int = 0
    @Published var p2Score: Int = 0

    @Published var showResults: Bool = false
    @Published var winner: Int? = nil               // 1 = P1, 2 = P2, 0 = tie

    private var timer: AnyCancellable?

    func startRound() {
        p1Score = 0
        p2Score = 0
        timeRemaining = 30
        roundActive = false
        raceStarted = false
        startCountdown = 3.0
        showResults = false
        winner = nil

        timer?.cancel()
        timer = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                // Phase 1: pre-start countdown
                if !self.raceStarted {
                    self.startCountdown -= 0.016
                    if self.startCountdown <= 0 {
                        self.startCountdown = 0
                        self.raceStarted = true
                        self.roundActive = true
                    }
                    return
                }

                // Phase 2: running round
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
                    // Give UI ~1.2s to flash winner
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if !self.roundActive && self.raceStarted { self.showResults = true }
                    }
                }
            }
    }

    func endRound() {
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
