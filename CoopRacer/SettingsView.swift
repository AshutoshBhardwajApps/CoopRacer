import SwiftUI
#if DEBUG
import GoogleMobileAds
#endif

/// Ported from CoopHockey's SettingsView, minus the NEMESIS and Game Center
/// sections this app doesn't have.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    var body: some View {
        Form {
            Section("PLAYER NAMES") {
                TextField("Player 1", text: $settings.player1Name)
                TextField("Player 2", text: $settings.player2Name)
            }

            Section("SOUND") {
                Toggle("Sound Effects & Haptics", isOn: $settings.effectsEnabled)
                Toggle("Background Music",        isOn: $settings.musicEnabled)
            }

            Section("ADS") {
                if settings.hasRemovedAds {
                    Label("Ads removed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button {
                        Task { await purchaseManager.buyRemoveAds() }
                    } label: {
                        HStack {
                            if purchaseManager.isLoading { ProgressView() }
                            else { Text("Remove Ads") }
                        }
                    }
                    .disabled(purchaseManager.isLoading)

                    Button("Restore Purchases") {
                        Task { await purchaseManager.restorePurchases() }
                    }
                    .disabled(purchaseManager.isLoading)

                    if let msg = purchaseManager.errorMessage {
                        Text(msg).font(.footnote).foregroundColor(.red)
                    }
                }
            }

            #if DEBUG
            Section("DEBUG") {
                Button("Reset consent (UMP form shows next launch)") {
                    ConsentManager.shared.reset()
                }

                Button("Ad Inspector") {
                    guard let top = AdManager.topmostPresenterVC() else { return }
                    MobileAds.shared.presentAdInspector(from: top) { error in
                        if let error { print("[AdInspector] \(error.localizedDescription)") }
                    }
                }
            }
            #endif

            Section("ABOUT") {
                NavigationLink {
                    CreditsView()
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Credits")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task { await purchaseManager.loadProducts() }
        .onChange(of: settings.musicEnabled) { enabled in
            Task { @MainActor in
                if enabled { BGM.shared.play(volume: 0.24) } else { BGM.shared.stop() }
            }
        }
    }
}
