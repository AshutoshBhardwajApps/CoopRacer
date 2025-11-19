import Foundation
import SwiftUI

// MARK: - Speed Levels

enum SpeedLevel: String, CaseIterable, Identifiable, Codable {
    case easy, medium, hard, insane

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy:   return "Easy"
        case .medium: return "Medium"
        case .hard:   return "Hard"
        case .insane: return "Insane"
        }
    }
}

// MARK: - Settings Store

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    

    // Car asset names you already have in the project
    static let carOptions: [String] = [
        "Audi", "Police", "Mini_truck", "Mini_van",
        "taxi", "Black_viper", "Car", "Ambulance", "truck"
    ]

    // Player names & cars
    @Published var player1Name: String { didSet { saveBasics() } }
    @Published var player2Name: String { didSet { saveBasics() } }
    @Published var player1Car: String  { didSet { saveBasics() } }
    @Published var player2Car: String  { didSet { saveBasics() } }

    // Selected speed level (used once unlocked)
    @Published var selectedSpeedLevel: SpeedLevel { didSet { saveProgress() } }

    // Progress towards unlocking speed levels
    @Published private(set) var totalRoundsPlayed: Int
    @Published private(set) var p1WinsTotal: Int
    @Published private(set) var p2WinsTotal: Int
    @Published private(set) var speedLevelsUnlocked: Bool

    // Computed helpers
    /// How many more rounds needed before the "10 rounds" condition is met.
    var remainingRoundsToUnlock: Int {
        max(0, 10 - totalRoundsPlayed)
    }

    /// Highest win rate between the two players.
    var highestWinRate: Double {
        guard totalRoundsPlayed > 0 else { return 0 }
        let topWins = max(p1WinsTotal, p2WinsTotal)
        return Double(topWins) / Double(totalRoundsPlayed)
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard

        // Basics
        self.player1Name = d.string(forKey: "settings.p1.name") ?? "PLAYER 1"
        self.player2Name = d.string(forKey: "settings.p2.name") ?? "PLAYER 2"
        self.player1Car  = d.string(forKey: "settings.p1.car")  ?? "Audi"
        self.player2Car  = d.string(forKey: "settings.p2.car")  ?? "Police"

        // Progress / difficulty
        let storedLevelRaw = d.string(forKey: "settings.speed.level")
        self.selectedSpeedLevel = SpeedLevel(rawValue: storedLevelRaw ?? "") ?? .easy

        self.totalRoundsPlayed  = d.integer(forKey: "settings.totalRounds")
        self.p1WinsTotal        = d.integer(forKey: "settings.p1WinsTotal")
        self.p2WinsTotal        = d.integer(forKey: "settings.p2WinsTotal")
        self.speedLevelsUnlocked = d.bool(forKey: "settings.speedUnlocked")
    }

    // MARK: - Public API

    /// Call this from GameCoordinator at the end of each round.
    /// `winner`: 1 = P1, 2 = P2, 0 or nil = tie.
    func registerRoundResult(winner: Int?) {
        totalRoundsPlayed += 1

        if winner == 1 {
            p1WinsTotal += 1
        } else if winner == 2 {
            p2WinsTotal += 1
        }

        // Unlock condition: at least 10 rounds AND ≥ 90% win rate for one player
        if !speedLevelsUnlocked,
           totalRoundsPlayed >= 10,
           highestWinRate >= 0.9 {
            speedLevelsUnlocked = true
        }

        saveProgress()
    }

    // Optional helper if you ever want to reset progress from a Settings screen
    func resetProgress() {
        totalRoundsPlayed = 0
        p1WinsTotal = 0
        p2WinsTotal = 0
        speedLevelsUnlocked = false
        selectedSpeedLevel = .easy
        saveProgress()
    }

    // MARK: - Persistence

    private func saveBasics() {
        let d = UserDefaults.standard
        d.set(player1Name, forKey: "settings.p1.name")
        d.set(player2Name, forKey: "settings.p2.name")
        d.set(player1Car,  forKey: "settings.p1.car")
        d.set(player2Car,  forKey: "settings.p2.car")
    }

    private func saveProgress() {
        let d = UserDefaults.standard
        d.set(selectedSpeedLevel.rawValue, forKey: "settings.speed.level")
        d.set(totalRoundsPlayed,           forKey: "settings.totalRounds")
        d.set(p1WinsTotal,                 forKey: "settings.p1WinsTotal")
        d.set(p2WinsTotal,                 forKey: "settings.p2WinsTotal")
        d.set(speedLevelsUnlocked,         forKey: "settings.speedUnlocked")
    }
}
