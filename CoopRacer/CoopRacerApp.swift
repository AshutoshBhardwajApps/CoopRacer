// CoopRacerApp.swift
import SwiftUI

@main
struct CoopRacerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var settings        = SettingsStore.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var gameCenter      = GameCenterManager.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .background(AdPresenter())   // <= mount anchor here (app root)
                .environmentObject(settings)
                .environmentObject(purchaseManager)
                .environmentObject(gameCenter)
                .preferredColorScheme(.dark)
                .task {
                    // Game Center may present its own sign-in sheet, so this
                    // runs from .task rather than the AppDelegate.
                    gameCenter.authenticate()
                    await purchaseManager.loadProducts()
                    await purchaseManager.restorePurchases()
                }
        }
    }
}
