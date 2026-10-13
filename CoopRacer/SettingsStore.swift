import Foundation
import SwiftUI

/// Player-facing settings and purchase state, ported from CoopHockey.
///
/// Every key is prefixed `cr.` so nothing collides with another app sharing a
/// UserDefaults suite. Each `@Published` field saves itself in `didSet`, so
/// view code never calls `save()` directly.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Must match the product ID created in App Store Connect letter-for-letter.
    static let removeAdsProductID = "coopracer.removeads"

    @Published var player1Name: String   { didSet { save() } }
    @Published var player2Name: String   { didSet { save() } }
    @Published var musicEnabled: Bool    { didSet { save() } }
    @Published var effectsEnabled: Bool  { didSet { save() } }
    @Published var hasRemovedAds: Bool   { didSet { save() } }

    @Published private(set) var totalRoundsPlayed: Int
    @Published private(set) var p1WinsTotal: Int
    @Published private(set) var p2WinsTotal: Int

    private init() {
        let d = UserDefaults.standard
        player1Name    = d.string(forKey: "cr.p1.name")         ?? "PLAYER 1"
        player2Name    = d.string(forKey: "cr.p2.name")         ?? "PLAYER 2"
        musicEnabled   = d.object(forKey: "cr.music")   as? Bool ?? true
        effectsEnabled = d.object(forKey: "cr.effects") as? Bool ?? true
        hasRemovedAds  = d.bool(forKey: "cr.removeAds")
        totalRoundsPlayed = d.integer(forKey: "cr.roundsPlayed")
        p1WinsTotal       = d.integer(forKey: "cr.p1Wins")
        p2WinsTotal       = d.integer(forKey: "cr.p2Wins")
    }

    /// `winner` follows GameCoordinator: 1 = P1, 2 = P2, 0 = tie.
    func registerResult(winner: Int?) {
        totalRoundsPlayed += 1
        if winner == 1 { p1WinsTotal += 1 }
        if winner == 2 { p2WinsTotal += 1 }
        save()
    }

    func markRemoveAdsPurchased() { hasRemovedAds = true }

    private func save() {
        let d = UserDefaults.standard
        d.set(player1Name,       forKey: "cr.p1.name")
        d.set(player2Name,       forKey: "cr.p2.name")
        d.set(musicEnabled,      forKey: "cr.music")
        d.set(effectsEnabled,    forKey: "cr.effects")
        d.set(hasRemovedAds,     forKey: "cr.removeAds")
        d.set(totalRoundsPlayed, forKey: "cr.roundsPlayed")
        d.set(p1WinsTotal,       forKey: "cr.p1Wins")
        d.set(p2WinsTotal,       forKey: "cr.p2Wins")
    }
}
