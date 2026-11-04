import SwiftUI

struct HighScoresView: View {
    @EnvironmentObject var scores: HighScoresStore
    @State private var tab: Tab = .endless

    enum Tab: String, CaseIterable {
        case endless   = "Endless"
        case twoPlayer = "Two Player"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("Mode", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if tab == .endless {
                EndlessLeaderboard(scores: scores)
            } else {
                TwoPlayerLeaderboard(scores: scores)
            }
        }
        .navigationTitle("High Scores")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Endless leaderboard

private struct EndlessLeaderboard: View {
    @ObservedObject var scores: HighScoresStore

    var body: some View {
        List {
            if scores.endlessScores.isEmpty {
                Text("No endless runs yet. Survive as long as you can!")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(scores.endlessScores.enumerated()), id: \.element.id) { rank, s in
                    HStack(spacing: 14) {
                        // Rank badge
                        ZStack {
                            Circle()
                                .fill(badgeColor(rank: rank))
                                .frame(width: 32, height: 32)
                            Text("\(rank + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.playerName)
                                .font(.headline)
                            Text(s.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(s.distance)m")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(rank == 0 ? Color.orange : .primary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: scores.deleteEndless)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !scores.endlessScores.isEmpty {
                    EditButton()
                    Button("Clear") { scores.clearEndless() }
                }
            }
        }
    }

    private func badgeColor(rank: Int) -> Color {
        switch rank {
        case 0: return .orange
        case 1: return Color(white: 0.6)
        case 2: return Color(red: 0.7, green: 0.45, blue: 0.2)
        default: return Color(white: 0.3)
        }
    }
}

// MARK: - Two-player leaderboard

private struct TwoPlayerLeaderboard: View {
    @ObservedObject var scores: HighScoresStore

    var body: some View {
        List {
            if scores.scores.isEmpty {
                Text("No scores yet. Play a two-player round!")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(scores.scores) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(s.player1Name) vs \(s.player2Name)")
                                .font(.headline)
                            Text(s.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(s.player1Score) – \(s.player2Score)")
                            .font(.title3.monospacedDigit())
                            .bold()
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: scores.delete)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !scores.scores.isEmpty {
                    EditButton()
                    Button("Clear") { scores.clear() }
                }
            }
        }
    }
}
