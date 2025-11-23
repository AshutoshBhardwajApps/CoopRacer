import Foundation
import SwiftUI

// MARK: - Solo High Score Model

struct SoloHighScore: Identifiable, Codable {
    let id: UUID
    let date: Date
    let playerName: String
    let score: Int
    let speedLevelRaw: String   // store as raw String for persistence

    var speedLevel: SpeedLevel {
        SpeedLevel(rawValue: speedLevelRaw) ?? .easy
    }
}

// MARK: - Solo High Scores Store

@MainActor
final class SoloHighScoresStore: ObservableObject {
    // ✅ Singleton used by SoloGameView & injected in CoopRacerApp
    static let shared = SoloHighScoresStore()

    @Published private(set) var scores: [SoloHighScore] = []

    private init() {
        load()
    }

    // Add a new solo score
    func add(playerName: String, score: Int, speedLevel: SpeedLevel) {
        let new = SoloHighScore(
            id: UUID(),
            date: Date(),
            playerName: playerName,
            score: score,
            speedLevelRaw: speedLevel.rawValue
        )

        scores.insert(new, at: 0)

        // Keep only top 10 (or adjust as you like)
        if scores.count > 10 {
            scores.removeLast(scores.count - 10)
        }

        save()
    }

    // Clear all solo scores
    func clear() {
        scores.removeAll()
        save()
    }

    // Delete specific rows
    func delete(at offsets: IndexSet) {
        scores.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Persistence

    private let key = "solo.scores.v1"

    private func load() {
        let d = UserDefaults.standard
        guard let data = d.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([SoloHighScore].self, from: data) {
            self.scores = decoded
        }
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(scores) {
            d.set(data, forKey: key)
        }
    }
}
