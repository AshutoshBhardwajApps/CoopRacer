import UIKit

/// Tactile feedback for crashes, the countdown and the round result, ported
/// from CoopHockey. Gated by `SettingsStore.effectsEnabled`, and always
/// dispatched to the main thread because UIFeedbackGenerator must run there.
final class Haptics {
    static let shared = Haptics()

    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact  = UIImpactFeedbackGenerator(style: .heavy)
    private let notify       = UINotificationFeedbackGenerator()

    private init() {
        DispatchQueue.main.async { [self] in
            lightImpact.prepare()
            heavyImpact.prepare()
            notify.prepare()
        }
    }

    /// A car hit an obstacle.
    func crash() {
        guard SettingsStore.shared.effectsEnabled else { return }
        DispatchQueue.main.async { [self] in
            heavyImpact.impactOccurred()
            heavyImpact.prepare()
        }
    }

    /// 3, 2, 1 of the start countdown.
    func countdownTick() {
        guard SettingsStore.shared.effectsEnabled else { return }
        DispatchQueue.main.async { [self] in
            lightImpact.impactOccurred(intensity: 0.6)
            lightImpact.prepare()
        }
    }

    /// GO, and the end of a round.
    func success() {
        guard SettingsStore.shared.effectsEnabled else { return }
        DispatchQueue.main.async { [self] in
            notify.notificationOccurred(.success)
            notify.prepare()
        }
    }
}
