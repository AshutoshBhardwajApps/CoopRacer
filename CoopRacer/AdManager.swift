import Foundation
import GoogleMobileAds
import UIKit

extension Notification.Name {
    static let adWillPresent = Notification.Name("AdManager.adWillPresent")
    static let adDidDismiss  = Notification.Name("AdManager.adDidDismiss")
}

@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    // ✅ Production interstitial unit ID (CoopRacer)
    // Old test ID was: "ca-app-pub-3940256099942544/4411468910"
    private let interstitialID = "ca-app-pub-2320635595451132/37805247221"

    // Gates
    private let minGapSeconds: TimeInterval = 0
    private let minRoundsBetweenAds: Int = 1

    // State
    private var lastShown: Date? = nil
    private var roundsSinceLastAd: Int = 0
    private var interstitial: InterstitialAd?

    private override init() { super.init() }

    // MARK: - Purchase Check (Remove Ads)
    private var adsDisabled: Bool {
        SettingsStore.shared.hasRemovedAds
    }

    // MARK: - Preload
    func preload() {
        if adsDisabled {
            print("[AdManager] Ads disabled — skipping preload.")
            interstitial = nil
            return
        }

        print("[AdManager] Preload start")
        let request = Request()

        InterstitialAd.load(with: interstitialID, request: request) { [weak self] ad, error in
            guard let self else { return }

            if self.adsDisabled {
                print("[AdManager] Ads disabled (after load) — discarding loaded ad.")
                return
            }

            if let ad = ad {
                ad.fullScreenContentDelegate = self
                self.interstitial = ad
                print("[AdManager] ✅ Interstitial loaded & cached")
            } else {
                print("[AdManager] ❌ Load failed: \(error?.localizedDescription ?? "unknown") — retry in 10s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.preload()
                }
            }
        }
    }

    // MARK: - Round Completed
    func noteRoundCompleted() {
        if adsDisabled {
            print("[AdManager] Ads disabled — not tracking rounds.")
            return
        }
        roundsSinceLastAd += 1
        print("[AdManager] Rounds since last ad: \(roundsSinceLastAd)")
    }

    // MARK: - Present Interstitial
    func presentIfAllowed(completion: ((Bool) -> Void)? = nil) {

        if adsDisabled {
            print("[AdManager] Ads disabled — skipping present.")
            completion?(false)
            return
        }

        // 0) Ensure active app
        guard UIApplication.shared.applicationState == .active else {
            print("[AdManager] Skip: app not active; retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }

        // 1) Round gate
        guard roundsSinceLastAd >= minRoundsBetweenAds else {
            print("[AdManager] Skip: need \(minRoundsBetweenAds - roundsSinceLastAd) more rounds.")
            completion?(false)
            return
        }

        // 2) Time gap
        let now = Date()
        if let last = lastShown, now.timeIntervalSince(last) < minGapSeconds {
            print("[AdManager] Skip: time gap not met.")
            completion?(false)
            return
        }

        // 3) Presenter available
        guard let rootVC = Self.presenterVC() else {
            print("[AdManager] Presenter not ready, retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard rootVC.presentedViewController == nil else {
            print("[AdManager] Presenter busy — retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }

        // 4) Ensure ad cached
        guard let ad = interstitial else {
            print("[AdManager] Not ready — preloading now.")
            preload()
            completion?(false)
            return
        }

        // 5) Present
        print("[AdManager] Presenting interstitial…")
        ad.present(from: rootVC)

        // Reset
        lastShown = now
        roundsSinceLastAd = 0
        interstitial = nil

        // Preload next
        preload()

        completion?(true)
    }

    // MARK: - Presenter helpers

    private static func presenterVC() -> UIViewController? {
        if let vc = AdPresenter.holder, vc.viewIfLoaded?.window != nil {
            return vc
        }

        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let root = scenes.first?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController

        return topViewController(base: root)
    }

    private static func topViewController(base: UIViewController?) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController,
           let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

// MARK: - Ad Delegate

extension AdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] ▶️ adWillPresentFullScreenContent")
        NotificationCenter.default.post(name: .adWillPresent, object: nil)
    }

    func ad(_ ad: any FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("[AdManager] ❌ Failed to present: \(error.localizedDescription)")
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] ⏹ adDidDismissFullScreenContent")
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }

    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] 👁 Impression")
    }

    func adDidRecordClick(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] 🖱 Click")
    }
}
