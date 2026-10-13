// CoopRacerApp.swift
import SwiftUI

@main
struct CoopRacerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var settings        = SettingsStore.shared
    @StateObject private var purchaseManager = PurchaseManager.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .background(AdPresenter())   // <= mount anchor here (app root)
                .environmentObject(settings)
                .environmentObject(purchaseManager)
                .preferredColorScheme(.dark)
                .task {
                    await purchaseManager.loadProducts()
                    await purchaseManager.restorePurchases()
                }
        }
    }
}
