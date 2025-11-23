import SwiftUI

struct HighScoresView: View {
    @EnvironmentObject var twoPlayer: HighScoresStore
    @EnvironmentObject var solo: SoloHighScoresStore

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Single Player
                Section("Single Player") {
                    if solo.scores.isEmpty {
                        Text("No single player scores yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(solo.scores) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.playerName)
                                        .font(.headline)
                                    Text(entry.date, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(entry.score)")
                                    .font(.title3.monospacedDigit())
                            }
                        }
                        .onDelete(perform: solo.delete)
                    }
                }

                // MARK: - Two Player
                Section("Two Player") {
                    if twoPlayer.scores.isEmpty {
                        Text("No two-player scores yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(twoPlayer.scores) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(entry.player1Name) vs \(entry.player2Name)")
                                        .font(.headline)
                                    Text(entry.date, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(entry.player1Score) : \(entry.player2Score)")
                                    .font(.title3.monospacedDigit())
                            }
                        }
                        .onDelete(perform: twoPlayer.delete)
                    }
                }
            }
            .navigationTitle("High Scores")
        }
    }
}
