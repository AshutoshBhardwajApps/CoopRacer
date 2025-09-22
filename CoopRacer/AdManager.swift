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

    // TEST interstitial (swap for real ID before release)
    private let interstitialID = "ca-app-pub-3940256099942544/4411468910"

    // Gates (tune for prod; set 0 / 1 while testing)
    private let minGapSeconds: TimeInterval = 0   // 5 min
    private let minRoundsBetweenAds: Int = 1        // 3 rounds

    // State
    private var lastShown: Date? = nil
    private var roundsSinceLastAd: Int = 0
    private var interstitial: InterstitialAd?

    private override init() { super.init() }

    // MARK: Load

    func preload() {
        let request = Request()
        print("[AdManager] Preload start")
        InterstitialAd.load(with: interstitialID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            if let ad = ad {
                ad.fullScreenContentDelegate = self
                self.interstitial = ad
                print("[AdManager] ✅ Interstitial loaded & cached")
            } else {
                print("[AdManager] ❌ Load failed: \(error?.localizedDescription ?? "unknown"); retrying in 10s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.preload()
                }
            }
        }
    }

    // Call when a round ends (e.g., Results appears)
    func noteRoundCompleted() {
        roundsSinceLastAd += 1
        print("[AdManager] Rounds since last ad: \(roundsSinceLastAd)")
    }

    // MARK: Present
    func presentIfAllowed(completion: ((Bool) -> Void)? = nil) {
        // 0) App must be active & on main
        guard UIApplication.shared.applicationState == .active else {
            print("[AdManager] Skip: app not active; retry 0.25s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }

        // 1) Round-count gate
        guard roundsSinceLastAd >= minRoundsBetweenAds else {
            print("[AdManager] Skip: need \(minRoundsBetweenAds - roundsSinceLastAd) more rounds.")
            completion?(false)
            return
        }

        // 2) Time-gap gate
        let now = Date()
        if let last = lastShown, now.timeIntervalSince(last) < minGapSeconds {
            let remaining = Int(minGapSeconds - now.timeIntervalSince(last))
            print("[AdManager] Skip: time cap \(remaining)s remaining.")
            completion?(false)
            return
        }

        // 3) Presenter readiness (use stable anchor; retry if mid-transition)
        guard let rootVC = Self.presenterVC() else {
            print("[AdManager] Presenter not ready; retry 0.25s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard rootVC.viewIfLoaded?.window != nil, rootVC.presentedViewController == nil else {
            print("[AdManager] Presenter busy or off-window; retry 0.25s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }

        // 4) Need a cached ad
        guard let ad = interstitial else {
            print("[AdManager] Skip: interstitial not ready. Preloading…")
            preload()
            completion?(false)
            return
        }

        // 5) Present
        print("[AdManager] Presenting interstitial…")
        ad.present(from: rootVC)

        // 6) Reset & warm next
        lastShown = now
        roundsSinceLastAd = 0
        interstitial = nil
        preload()

        // Report: ad was shown
        completion?(true)
    }
    // MARK: Presenter helpers

    private static func presenterVC() -> UIViewController? {
        if let vc = AdPresenter.holder, vc.viewIfLoaded?.window != nil {
            return vc
        }
        // Fallback to top-most
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
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

// MARK: - Full-screen content delegate (diagnostics)
extension AdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] ▶️ adWillPresentFullScreenContent")
        NotificationCenter.default.post(name: .adWillPresent, object: nil)
    }

    // v12+: adDidPresent... is unavailable/removed

    func ad(_ ad: any FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("[AdManager] ❌ didFailToPresent: \(error.localizedDescription)")
        // Treat as dismissed to be safe:
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] ⏹ adDidDismissFullScreenContent")
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }

    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] 👁 adDidRecordImpression")
    }

    func adDidRecordClick(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] 🖱 adDidRecordClick")
    }
}
