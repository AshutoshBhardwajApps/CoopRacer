import Foundation
import SwiftUI

// MARK: - Two-player score entry

struct HighScore: Identifiable, Codable {
    let id: UUID
    let date: Date
    let player1Name: String
    let player2Name: String
    let player1Score: Int
    let player2Score: Int
}

// MARK: - Endless mode score entry

struct EndlessScore: Identifiable, Codable {
    let id: UUID
    let date: Date
    let playerName: String
    let distance: Int           // metres
}

// MARK: - Store

@MainActor
final class HighScoresStore: ObservableObject {
    static let shared = HighScoresStore()

    @Published private(set) var scores: [HighScore] = []
    @Published private(set) var endlessScores: [EndlessScore] = []

    private init() { load() }

    // MARK: - Two-player

    func add(p1Name: String, p2Name: String, p1Score: Int, p2Score: Int) {
        let new = HighScore(
            id: UUID(),
            date: Date(),
            player1Name: p1Name,
            player2Name: p2Name,
            player1Score: p1Score,
            player2Score: p2Score
        )
        scores.insert(new, at: 0)
        if scores.count > 10 { scores.removeLast(scores.count - 10) }
        save()
    }

    func clear() {
        scores.removeAll()
        save()
    }

    func delete(at offsets: IndexSet) {
        scores.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Endless

    func addEndless(playerName: String, distance: Int) {
        let new = EndlessScore(
            id: UUID(),
            date: Date(),
            playerName: playerName,
            distance: distance
        )
        endlessScores.append(new)
        // Keep top 10 by distance
        endlessScores.sort { $0.distance > $1.distance }
        if endlessScores.count > 10 { endlessScores.removeLast(endlessScores.count - 10) }
        saveEndless()
    }

    func clearEndless() {
        endlessScores.removeAll()
        saveEndless()
    }

    func deleteEndless(at offsets: IndexSet) {
        endlessScores.remove(atOffsets: offsets)
        saveEndless()
    }

    // MARK: - Persistence

    private let key        = "scores.v1"
    private let endlessKey = "scores.endless.v1"

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HighScore].self, from: data) {
            self.scores = decoded
        }
        if let data = d.data(forKey: endlessKey),
           let decoded = try? JSONDecoder().decode([EndlessScore].self, from: data) {
            self.endlessScores = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scores) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func saveEndless() {
        if let data = try? JSONEncoder().encode(endlessScores) {
            UserDefaults.standard.set(data, forKey: endlessKey)
        }
    }
}
