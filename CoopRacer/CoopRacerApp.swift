// CoopRacerApp.swift
import SwiftUI

@main
struct CoopRacerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = SettingsStore.shared
       @StateObject private var scores   = HighScoresStore.shared
    var body: some Scene {
        WindowGroup {
            HomeView()
                .background(AdPresenter())   // <= mount anchor here (app root)
                .environmentObject(settings)
                              .environmentObject(scores)
        }
    }
}
