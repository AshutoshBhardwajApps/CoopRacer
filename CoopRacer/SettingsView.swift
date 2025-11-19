import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            // MARK: - Names
            Section("PLAYER NAMES") {
                TextField("Player 1", text: $settings.player1Name)
                TextField("Player 2", text: $settings.player2Name)
            }

            // MARK: - Cars
            Section("PLAYER 1 CAR") {
                CarGrid(selection: $settings.player1Car)
            }

            Section("PLAYER 2 CAR") {
                CarGrid(selection: $settings.player2Car)
            }

            // MARK: - Speed Levels
            Section("SPEED LEVELS") {
                if settings.speedLevelsUnlocked {
                    Picker("Speed Level", selection: $settings.selectedSpeedLevel) {
                        ForEach(SpeedLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }

                    Text("You’ve unlocked difficulty levels. Choose how intense you want the race to be.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Speed Levels Locked")
                            .font(.headline)

                        Text("Play \(settings.remainingRoundsToUnlock) more rounds and win at least 90% of them to unlock difficulty levels.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        if settings.totalRoundsPlayed > 0 {
                            let rate = Int(settings.highestWinRate * 100)
                            Text("Current best win rate: \(rate)% over \(settings.totalRoundsPlayed) rounds.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Car selection

private struct CarGrid: View {
    @Binding var selection: String
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SettingsStore.carOptions, id: \.self) { assetName in

                let label = displayName(for: assetName)

                CarThumb(assetName: assetName,
                         label: label,
                         selected: selection == assetName)
                    .onTapGesture { selection = assetName }
            }
        }
        .padding(.vertical, 6)
    }
    
    /// Maps asset names → clean labels
      private func displayName(for asset: String) -> String {
          switch asset {
          case "Car":
              return "Car 1"
          case "Audi":
              return "Car 2"
          case "Black_viper", "Viper":
              return "Car 3"
          default:
              // Generic clean-up: remove `_` and capitalize words
              let cleaned = asset
                  .replacingOccurrences(of: "_", with: " ")
              return cleaned.capitalized   // "Mini_truck" → "Mini Truck"
          }
      }
  }

private struct CarThumb: View {
    let assetName: String   // actual asset name used in UIImage / SKTexture
    let label: String       // cleaned display label
    let selected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? Color.blue : Color.white.opacity(0.15),
                                lineWidth: selected ? 2 : 1)
                )

            VStack(spacing: 8) {
                carImage
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 64)

                Text(label)              // 👈 clean label, no underscores
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(10)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var carImage: Image {
        #if canImport(UIKit)
        if let ui = UIImage(named: assetName) {
            return Image(uiImage: ui)
        }
        #endif
        return Image(systemName: "car.fill")
    }
}
