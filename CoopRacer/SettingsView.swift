import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager

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

            // MARK: - Sound
            Section("SOUND") {
                Toggle("Sound Effects", isOn: $settings.effectsEnabled)
                Toggle("Background Music", isOn: $settings.musicEnabled)
            }

            // MARK: - Ads / IAP
            Section("ADS") {
                if settings.hasRemovedAds {
                    Label("Ads removed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button {
                        Task {
                            await purchaseManager.buyRemoveAds()
                        }
                    } label: {
                        HStack {
                            if purchaseManager.isLoading {
                                ProgressView()
                            } else {
                                Text("Remove Ads")
                            }
                        }
                    }
                    .disabled(purchaseManager.isLoading)

                    Button("Restore Purchases") {
                        Task {
                            await purchaseManager.restorePurchases()
                        }
                    }
                    .disabled(purchaseManager.isLoading)

                    if let msg = purchaseManager.errorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            // Load product info when Settings appears
            await purchaseManager.loadProducts()
        }
        // 🔊 Immediate reaction to BACKGROUND MUSIC toggle
        .onChange(of: settings.musicEnabled) { enabled in
            Task { @MainActor in
                if enabled {
                    // Resume / start loop at a safe volume
                    BGM.shared.play(volume: 0.24)
                } else {
                    // Instantly silence background music without app restart
                    BGM.shared.stop()
                }
            }
        }
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
            let cleaned = asset.replacingOccurrences(of: "_", with: " ")
            return cleaned.capitalized
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

                Text(label)
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
