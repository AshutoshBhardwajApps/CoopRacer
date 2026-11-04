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

    /// Debug builds use Google's always-filling interstitial test unit, so
    /// development never touches the real one. Release uses the production
    /// unit; registered test devices (AppDelegate) still get test ads.
    #if DEBUG
    private let interstitialID = "ca-app-pub-3940256099942544/4411468910"
    #else
    // CoopRacer_Interstitial_Main in the AdMob console.
    private let interstitialID = "ca-app-pub-2320635595451132/3705247221"
    #endif

    /// Same pacing as CoopHockey: an interstitial may follow every completed
    /// round. Rounds are a fixed 30s, so this is roughly one ad per 35s of play
    /// at most; raise `minGapSeconds` if reviews complain.
    private let minRoundsBetweenAds: Int = 1
    private let minGapSeconds: TimeInterval = 0

    /// Guarantee a Remove Ads promo every Nth completed round, bypassing the
    /// random odds and ad-pacing gates. Random promo rolls still happen on
    /// other rounds — this is a floor, not a ceiling.
    private let forcePromoEvery: Int = 8

    private var lastShown: Date?
    private var roundsSinceLastAd = 0
    private var roundsSincePromo = 0
    private var interstitial: InterstitialAd?

    private override init() { super.init() }

    private var adsDisabled: Bool { SettingsStore.shared.hasRemovedAds }

    private var adUnitIsPlaceholder: Bool { interstitialID.contains("XXXX") }

    // MARK: - Preload

    func preload() {
        guard !adsDisabled else { interstitial = nil; return }
        guard !adUnitIsPlaceholder else {
            print("[AdManager] ❌ interstitial unit ID is still a placeholder — not requesting")
            return
        }
        InterstitialAd.load(with: interstitialID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            guard !self.adsDisabled else { return }
            if let ad {
                ad.fullScreenContentDelegate = self
                self.interstitial = ad
                print("[AdManager] ✅ loaded")
            } else {
                print("[AdManager] ❌ load failed: \(error?.localizedDescription ?? "unknown") — retry in 10s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.preload() }
            }
        }
    }

    // MARK: - Round tracking

    func noteRoundCompleted() {
        guard !adsDisabled else { return }
        roundsSinceLastAd += 1
        roundsSincePromo += 1
    }

    /// Whether to show the Remove Ads promo in place of an interstitial.
    /// Two paths:
    ///   1. Forced: guaranteed promo every Nth completed round, bypassing the
    ///      ad-pacing gates so it always lands.
    ///   2. Random: ~1-in-12 chance on other round-end slots, still gated by
    ///      the normal ad pacing.
    func shouldShowPromoInsteadOfAd() -> Bool {
        guard !adsDisabled else { return false }
        if roundsSincePromo >= forcePromoEvery { return true }
        guard roundsSinceLastAd >= minRoundsBetweenAds else { return false }
        if let last = lastShown, Date().timeIntervalSince(last) < minGapSeconds { return false }
        return Int.random(in: 0..<12) == 0
    }

    /// A promo "consumes" the ad slot the same way a real ad would.
    func notePromoShown() {
        roundsSinceLastAd = 0
        roundsSincePromo = 0
        lastShown = Date()
    }

    // MARK: - Present

    /// `completion(true)` only if an ad actually presented, so the caller can
    /// advance its flow either way (and wait for `.adDidDismiss` if it did).
    func presentIfAllowed(completion: ((Bool) -> Void)? = nil) {
        presentIfAllowed(giveUpAt: Date().addingTimeInterval(Self.presentRetryWindow),
                         completion: completion)
    }

    /// How long to keep retrying while the app is backgrounded or the anchor
    /// is covered. Without a bound, a player who leaves the results screen
    /// for the home menu would leave a retry ticking every 250ms forever.
    private static let presentRetryWindow: TimeInterval = 4

    private func presentIfAllowed(giveUpAt deadline: Date,
                                  completion: ((Bool) -> Void)?) {
        guard !adsDisabled else { completion?(false); return }
        let retry = { [weak self] in
            guard Date() < deadline else {
                print("[AdManager] gave up presenting — anchor stayed unavailable")
                completion?(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.presentIfAllowed(giveUpAt: deadline, completion: completion)
            }
        }
        guard UIApplication.shared.applicationState == .active else { retry(); return }
        guard roundsSinceLastAd >= minRoundsBetweenAds else { completion?(false); return }
        if let last = lastShown, Date().timeIntervalSince(last) < minGapSeconds {
            completion?(false); return
        }
        guard let rootVC = Self.presenterVC() else { retry(); return }
        // Was `rootVC.presentedViewController == nil`, which never fired.
        // rootVC is AdPresenter's anchor — a CHILD view controller inside the
        // SwiftUI tree — and a child has no presentedViewController of its
        // own even while the results sheet covers it. So the guard passed,
        // UIKit then refused the presentation because an ANCESTOR was
        // presenting, and the refusal was silent: 100% fill, zero
        // impressions, every round since launch.
        guard !Self.anchorIsCovered(rootVC) else { retry(); return }
        guard let ad = interstitial else { preload(); completion?(false); return }

        // Clear state only once the ad has actually been recorded. Doing it
        // immediately after present() meant a refused presentation still
        // consumed the ad and reset the pacing counters, so the next round
        // started from scratch with nothing loaded.
        ad.present(from: rootVC)
        completion?(true)
    }

    /// Is something presented over the anchor's own hierarchy?
    ///
    /// Walks the window's presentation chain and asks whether each presented
    /// controller belongs to the anchor's ancestry. A sheet shown as a
    /// sibling — the results screen, or one still animating away — does not,
    /// and presenting from beneath it is silently refused by UIKit.
    private static func anchorIsCovered(_ anchor: UIViewController) -> Bool {
        guard let root = anchor.view.window?.rootViewController else { return false }
        var ancestry = Set<ObjectIdentifier>()
        var node: UIViewController? = anchor
        while let n = node {
            ancestry.insert(ObjectIdentifier(n))
            node = n.parent
        }
        var presented = root.presentedViewController
        while let p = presented {
            if !ancestry.contains(ObjectIdentifier(p)) { return true }
            presented = p.presentedViewController
        }
        return false
    }

    // MARK: - Presenter helpers

    /// The controller actually on top of the presentation stack. Anything
    /// shown from *inside* a sheet or fullScreenCover must present from here,
    /// not from AdPresenter's anchor — UIKit refuses to present from a
    /// controller that is already presenting, and the failure is silent
    /// (CoopHockey ran 100% fill with zero impressions for weeks this way).
    static func topmostPresenterVC() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let root = scenes.first?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        return topViewController(base: root) ?? AdPresenter.holder
    }

    /// Interstitials fire at a round break with nothing covering the game, so
    /// they prefer AdPresenter's stable anchor. That lets `presentIfAllowed`
    /// see a sheet is already up and wait instead of failing.
    private static func presenterVC() -> UIViewController? {
        if let vc = AdPresenter.holder, vc.viewIfLoaded?.window != nil { return vc }
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let root = scenes.first?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        return topViewController(base: root)
    }

    private static func topViewController(base: UIViewController?) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController, let sel = tab.selectedViewController { return topViewController(base: sel) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}

// MARK: - Delegate

extension AdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        // It is really going on screen — now the ad is spent and the pacing
        // counters should restart.
        lastShown = Date()
        roundsSinceLastAd = 0
        interstitial = nil
        preload()
        NotificationCenter.default.post(name: .adWillPresent, object: nil)
    }

    /// The only callback that confirms AdMob actually counted the render.
    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        print("[AdManager] ✅ impression recorded")
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        // Loud on purpose. A present failure looks identical to a no-fill in
        // the AdMob report except for match rate.
        print("[AdManager] ❌ present failed: \(error.localizedDescription)")
        // Keep the ad and the counters: nothing was shown, so the next round
        // should get this same ad rather than starting over with none.
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }
}
