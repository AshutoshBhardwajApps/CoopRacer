import Foundation
import SwiftUI

struct HighScore: Identifiable, Codable {
    let id: UUID
    let date: Date
    let player1Name: String
    let player2Name: String
    let player1Score: Int
    let player2Score: Int
}

@MainActor
final class HighScoresStore: ObservableObject {
    // ✅ Singleton used by ContentView (HighScoresStore.shared.add(...))
    static let shared = HighScoresStore()

    @Published private(set) var scores: [HighScore] = []

    private init() { load() }   // private so we don’t create multiple instances

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
    // Delete one or more rows from the list
    func delete(at offsets: IndexSet) {
        scores.remove(atOffsets: offsets)
        save()
    }
    // MARK: - Persistence
    private let key = "scores.v1"

    private func load() {
        let d = UserDefaults.standard
        guard let data = d.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([HighScore].self, from: data) {
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
