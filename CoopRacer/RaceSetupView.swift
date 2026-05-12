import SwiftUI

struct RaceSetupView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var botCount: Int = SettingsStore.shared.preferredBotCount
    @State private var difficulty: BotDifficulty = SettingsStore.shared.preferredBotDifficulty

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {

                // Opponent count
                VStack(spacing: 10) {
                    Label("OPPONENTS", systemImage: "person.3.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(2)

                    HStack(spacing: 0) {
                        ForEach([1, 2, 3], id: \.self) { n in
                            Button {
                                botCount = n
                                settings.preferredBotCount = n
                            } label: {
                                VStack(spacing: 6) {
                                    HStack(spacing: -10) {
                                        ForEach(0..<n, id: \.self) { i in
                                            Image(systemName: "car.fill")
                                                .font(.title2)
                                                .foregroundStyle(botColor(i))
                                                .shadow(color: .black.opacity(0.5), radius: 2)
                                        }
                                    }
                                    Text(n == 1 ? "1 Bot" : "\(n) Bots")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 72)
                                .background(botCount == n
                                    ? Color.white.opacity(0.18)
                                    : Color.white.opacity(0.06))
                                .overlay(
                                    Rectangle()
                                        .stroke(botCount == n ? Color.white.opacity(0.55) : Color.clear,
                                                lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.horizontal, 28)

                // Difficulty picker
                VStack(spacing: 10) {
                    Label("DIFFICULTY", systemImage: "speedometer")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(2)

                    VStack(spacing: 8) {
                        ForEach(BotDifficulty.allCases) { diff in
                            let unlocked = diff <= settings.unlockedBotDifficulty
                            Button {
                                guard unlocked else { return }
                                difficulty = diff
                                settings.preferredBotDifficulty = diff
                            } label: {
                                DiffRow(diff: diff,
                                        selected: difficulty == diff,
                                        unlocked: unlocked,
                                        winsNeeded: winsNeeded(for: diff))
                            }
                            .buttonStyle(.plain)
                            .disabled(!unlocked)
                        }
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                // Race button
                NavigationLink {
                    ContentView(isSinglePlayer: true,
                                botCount: botCount,
                                botDifficulty: difficulty)
                        .navigationBarBackButtonHidden(true)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "flag.checkered.2.crossed")
                            .font(.headline)
                        Text("RACE!")
                            .font(.headline.weight(.black))
                            .tracking(2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.55, blue: 1.0),
                                     Color(red: 0.08, green: 0.28, blue: 0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 5)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
            .padding(.top, 24)
        }
        .navigationTitle("Solo Race")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Helpers

    private func botColor(_ index: Int) -> Color {
        [Color.red, Color.green, Color(hue: 0.78, saturation: 0.85, brightness: 0.95)][index]
    }

    private func winsNeeded(for diff: BotDifficulty) -> Int {
        switch diff {
        case .easy:       return 0
        case .medium:     return max(0, 1 - settings.soloWinsEasy)
        case .hard:       return max(0, 2 - settings.soloWinsMedium)
        case .relentless: return max(0, 1 - settings.soloWinsHard)
        }
    }
}

// MARK: - Difficulty row

private struct DiffRow: View {
    let diff: BotDifficulty
    let selected: Bool
    let unlocked: Bool
    let winsNeeded: Int

    var body: some View {
        HStack(spacing: 12) {
            // Lock / speed icon
            ZStack {
                Circle()
                    .fill(unlocked ? iconBg : Color.white.opacity(0.05))
                    .frame(width: 36, height: 36)
                Image(systemName: unlocked ? speedIcon : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(unlocked ? .white : .white.opacity(0.35))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(diff.label)
                    .font(.headline)
                    .foregroundStyle(unlocked ? .white : .white.opacity(0.38))
                Text(unlocked ? diff.description : diff.unlockRequirement)
                    .font(.caption)
                    .foregroundStyle(unlocked ? .white.opacity(0.55) : .white.opacity(0.30))
            }

            Spacer()

            if selected && unlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected && unlocked
                    ? Color.white.opacity(0.14)
                    : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected && unlocked ? Color.white.opacity(0.45) : Color.clear,
                        lineWidth: 1.5)
        )
    }

    private var iconBg: Color {
        switch diff {
        case .easy:       return Color(red: 0.20, green: 0.65, blue: 0.30)
        case .medium:     return Color(red: 0.85, green: 0.60, blue: 0.10)
        case .hard:       return Color(red: 0.80, green: 0.20, blue: 0.15)
        case .relentless: return Color(red: 0.55, green: 0.05, blue: 0.80)
        }
    }

    private var speedIcon: String {
        switch diff {
        case .easy:       return "tortoise.fill"
        case .medium:     return "hare.fill"
        case .hard:       return "bolt.fill"
        case .relentless: return "flame.fill"
        }
    }
}
