import SwiftUI

struct HighScoresView: View {
    @EnvironmentObject var scores: HighScoresStore

    var body: some View {
        List {
            if scores.scores.isEmpty {
                Text("No scores yet. Play a round!")
                    .foregroundStyle(.secondary)
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
                .onDelete(perform: scores.delete)   // swipe to delete
            }
        }
        .navigationTitle("High Scores")
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
