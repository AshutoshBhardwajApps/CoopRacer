// CoopRacerApp.swift
import SwiftUI

@main
struct CoopRacerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var settings        = SettingsStore.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var scores          = HighScoresStore.shared
    @StateObject private var gameCenter      = GameCenterManager.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .background(AdPresenter())   // anchor for interstitials
                .environmentObject(settings)
                .environmentObject(purchaseManager)
                .environmentObject(scores)
                .environmentObject(gameCenter)
                .task {
                    // Game Center may present its own sign-in sheet, so this
                    // runs from .task rather than the AppDelegate.
                    gameCenter.authenticate()
                    // ✅ Make sure IAP state is correct on launch
                    await purchaseManager.loadProducts()
                    await purchaseManager.restorePurchases()
                }
        }
    }
}
