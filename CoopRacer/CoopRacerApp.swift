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
                    // Hold every "runs once at launch" side-effect past the
                    // first frame so nothing can race the window becoming
                    // key. Apple's 1.3(11) review crash was not reproducible
                    // locally, so the working theory is a presentation race
                    // between Game Center's sign-in sheet, UMP consent and
                    // ATT. AppDelegate defers UMP+ATT to 2.0s; GC goes first
                    // at ~0.8s so its sheet, if any, is already up by then.
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    gameCenter.authenticate()

                    // IAP waits a bit more so StoreKit's first request does
                    // not compete with Game Center's network traffic. None
                    // of this is latency the user sees — HomeView is already
                    // interactive.
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    await purchaseManager.loadProducts()
                    await purchaseManager.restorePurchases()
                }
        }
    }
}
