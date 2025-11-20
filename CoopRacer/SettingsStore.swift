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

// MARK: - Settings Store (Pure State, No Audio Calls Here)

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // Under-the-hood asset names already in the project
    static let carOptions: [String] = [
        "Car", "Audi", "Black_viper", "Police",
        "Mini_truck", "Mini_van", "taxi",
        "Ambulance", "truck"
    ]

    static func displayName(for assetName: String) -> String {
        switch assetName {
        case "Car":          return "Car 1"
        case "Audi":         return "Car 2"
        case "Black_viper":  return "Car 3"
        default:
            return assetName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - In-App Purchase
    static let removeAdsProductID = "coopracer.removeads"

    @Published var hasRemovedAds: Bool {
        didSet { saveProgress() }
    }

    // MARK: - Sound Toggles (NO audio calls here!)
    @Published var musicEnabled: Bool {
        didSet { saveProgress() }
    }

    @Published var effectsEnabled: Bool {
        didSet { saveProgress() }
    }

    // MARK: - Names & Cars
    @Published var player1Name: String { didSet { saveBasics() } }
    @Published var player2Name: String { didSet { saveBasics() } }
    @Published var player1Car:  String { didSet { saveBasics() } }
    @Published var player2Car:  String { didSet { saveBasics() } }

    // MARK: - Speed Levels
    @Published var selectedSpeedLevel: SpeedLevel { didSet { saveProgress() } }

    @Published private(set) var totalRoundsPlayed: Int
    @Published private(set) var p1WinsTotal: Int
    @Published private(set) var p2WinsTotal: Int
    @Published private(set) var speedLevelsUnlocked: Bool

    var remainingRoundsToUnlock: Int {
        max(0, 10 - totalRoundsPlayed)
    }

    var highestWinRate: Double {
        guard totalRoundsPlayed > 0 else { return 0 }
        return Double(max(p1WinsTotal, p2WinsTotal)) / Double(totalRoundsPlayed)
    }

    // MARK: - Init
    private init() {
        let d = UserDefaults.standard

        player1Name = d.string(forKey: "settings.p1.name") ?? "PLAYER 1"
        player2Name = d.string(forKey: "settings.p2.name") ?? "PLAYER 2"
        player1Car  = d.string(forKey: "settings.p1.car")  ?? "Audi"
        player2Car  = d.string(forKey: "settings.p2.car")  ?? "Police"

        let storedLevel = d.string(forKey: "settings.speed.level")
        selectedSpeedLevel = SpeedLevel(rawValue: storedLevel ?? "") ?? .easy

        totalRoundsPlayed   = d.integer(forKey: "settings.totalRounds")
        p1WinsTotal         = d.integer(forKey: "settings.p1WinsTotal")
        p2WinsTotal         = d.integer(forKey: "settings.p2WinsTotal")
        speedLevelsUnlocked = d.bool(forKey: "settings.speedUnlocked")

        hasRemovedAds = d.bool(forKey: "settings.removeAdsPurchased")

        musicEnabled   = d.object(forKey: "settings.musicEnabled") as? Bool ?? true
        effectsEnabled = d.object(forKey: "settings.effectsEnabled") as? Bool ?? true
    }

    // MARK: - Public API

    func registerRoundResult(winner: Int?) {
        totalRoundsPlayed += 1
        if winner == 1 { p1WinsTotal += 1 }
        if winner == 2 { p2WinsTotal += 1 }

        if !speedLevelsUnlocked,
           totalRoundsPlayed >= 10,
           highestWinRate >= 0.9 {
            speedLevelsUnlocked = true
        }

        saveProgress()
    }

    func markRemoveAdsPurchased() {
        hasRemovedAds = true
    }

    func resetProgress() {
        totalRoundsPlayed = 0
        p1WinsTotal = 0
        p2WinsTotal = 0
        speedLevelsUnlocked = false
        selectedSpeedLevel = .easy
        saveProgress()
    }

    func resetPurchasesDebug() {
        hasRemovedAds = false
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
        d.set(hasRemovedAds,               forKey: "settings.removeAdsPurchased")
        d.set(musicEnabled,                forKey: "settings.musicEnabled")
        d.set(effectsEnabled,              forKey: "settings.effectsEnabled")
    }
}
