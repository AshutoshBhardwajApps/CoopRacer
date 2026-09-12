import UIKit
import GoogleMobileAds
import AVFAudio
import AppTrackingTransparency
import FBAudienceNetwork

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// One-shot guard so we only request ATT once per launch even if
    /// didBecomeActive fires multiple times (e.g. user toggled Control
    /// Center, returned to app, etc.).
    private var attRequested = false
    private var didBecomeActiveObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {

        // 1) Audio session up front (respect silent switch; mix if you want)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            // If you want app to sound even when the ringer switch is silent, use:
            // try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredIOBufferDuration(0.005) // small buffer helps reduce pops
            try session.setActive(true, options: [])
        } catch {
            print("Audio session init error: \(error)")
        }

        // Meta Audience Network (mediation bidding) needs its Advertiser
        // Tracking Enabled flag set before the Google Mobile Ads SDK
        // initializes its adapters. On first launch ATT is .notDetermined so
        // this starts false; requestATTIfNeeded() updates it once the user
        // answers the prompt (subsequent launches pick up the stored status).
        if #available(iOS 14, *) {
            FBAdSettings.setAdvertiserTrackingEnabled(
                ATTrackingManager.trackingAuthorizationStatus == .authorized
            )
        }

        // 2) (your existing lines)
        let ads = MobileAds.shared
        ads.start()
        AdManager.shared.preload()

        // ATT must be requested when the app is in the .active state. Calling
        // it from didFinishLaunching is too early — iOS silently no-ops the
        // request and the dialog never shows (this is exactly what App Store
        // review flagged in the 1.3(14) rejection). Defer to didBecomeActive
        // and add a small delay so the launch transition completes before the
        // system alert tries to present.
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestATTIfNeeded()
        }

        return true
    }

    private func requestATTIfNeeded() {
        guard !attRequested else { return }
        attRequested = true

        // Stop listening — one-shot.
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
            didBecomeActiveObserver = nil
        }

        // 0.4s delay lets the launch transition finish; without it the alert
        // can race with the first frame and either be dropped or appear
        // before the app's UI is visible (which Apple also dislikes).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization { status in
                    FBAdSettings.setAdvertiserTrackingEnabled(status == .authorized)
                    Task { @MainActor in AdManager.shared.preload() }
                }
            } else {
                Task { @MainActor in AdManager.shared.preload() }
            }
        }
    }
}
