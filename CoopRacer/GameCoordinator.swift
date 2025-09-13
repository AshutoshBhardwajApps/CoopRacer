//
//  GameCoordinator.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-09-13.
//

import Foundation
import Combine

final class GameCoordinator: ObservableObject {
    @Published var roundActive: Bool = true
    @Published var timeRemaining: Double = 30.0     // seconds
    @Published var p1Score: Int = 0
    @Published var p2Score: Int = 0
    @Published var showResults: Bool = false

    private var timer: AnyCancellable?

    func startRound() {
        p1Score = 0; p2Score = 0
        timeRemaining = 30
        roundActive = true
        showResults = false

        timer?.cancel()
        timer = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.roundActive else { return }
                self.timeRemaining -= 0.016
                if self.timeRemaining <= 0 {
                    self.timeRemaining = 0
                    self.roundActive = false
                    self.showResults = true
                    self.timer?.cancel()
                }
            }
    }

    func endRound() {
        roundActive = false
        showResults = true
        timer?.cancel()
    }

    func addScore(player1: Bool, points: Int) {
        if player1 { p1Score += points } else { p2Score += points }
    }
}
