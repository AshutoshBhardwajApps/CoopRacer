import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // Car asset names you already have in the project
    static let carOptions: [String] = [
        "Audi", "Police", "Mini_truck", "Mini_van",
        "taxi", "Black_viper", "Car", "Ambulance", "truck"
    ]

    @Published var player1Name: String { didSet { save() } }
    @Published var player2Name: String { didSet { save() } }
    @Published var player1Car: String  { didSet { save() } }
    @Published var player2Car: String  { didSet { save() } }

   private init() {
        let d = UserDefaults.standard
        self.player1Name = d.string(forKey: "settings.p1.name") ?? "PLAYER 1"
        self.player2Name = d.string(forKey: "settings.p2.name") ?? "PLAYER 2"
        self.player1Car  = d.string(forKey: "settings.p1.car")  ?? "Audi"
        self.player2Car  = d.string(forKey: "settings.p2.car")  ?? "Police"
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(player1Name, forKey: "settings.p1.name")
        d.set(player2Name, forKey: "settings.p2.name")
        d.set(player1Car,  forKey: "settings.p1.car")
        d.set(player2Car,  forKey: "settings.p2.car")
    }
}
