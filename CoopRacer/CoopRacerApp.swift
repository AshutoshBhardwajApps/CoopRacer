// CoopRacerApp.swift
import SwiftUI

@main
struct CoopRacerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var settings        = SettingsStore.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var scores          = HighScoresStore.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .background(AdPresenter())   // anchor for interstitials
                .environmentObject(settings)
                .environmentObject(purchaseManager)
                .environmentObject(scores)
                .task {
                    // ✅ Make sure IAP state is correct on launch
                    await purchaseManager.loadProducts()
                    await purchaseManager.restorePurchases()
                }
        }
    }
}
