import UIKit
import GoogleMobileAds
import AVFAudio
import AppTrackingTransparency

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// One-shot guard so we only request ATT once per launch even if
    /// didBecomeActive fires multiple times (e.g. user toggled Control
    /// Center, returned to app, etc.).
    private var attRequested = false
    private var didBecomeActiveObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            // setPreferredIOBufferDuration(0.005) was here. 5 ms is an
            // instrument-grade latency target that forces tiny render blocks;
            // on iPhone, where the fulfilled buffer can be ~1 ms, the audio
            // graph starves between callbacks and the mix crackles. Ambient
            // game music does not need low latency — let the system choose
            // (~23 ms) and the crackle goes away.
            try session.setActive(true, options: [])
        } catch {
            print("Audio session error: \(error)")
        }

        // Register test devices so real ad-unit IDs serve TEST ads on these devices.
        // Find your device's hashed ID in the Xcode console after the first ad request:
        //   "To get test ads on this device, set: Mobile Ads SDK ... testDeviceIdentifiers = @[ @"ABC123..." ]"
        // Paste that hash into the array below. Safe to ship with real device IDs in production —
        // it only affects the listed devices.
        // This hash is derived from the device's advertising identifier, so it
        // changes if that identifier is reset — at which point the device
        // silently starts serving REAL ads to you. Re-read it from the console
        // ("To get test ads on this device, set: ...") whenever that happens.
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "c18f2644337b99f078c7f88f6136a82f", // Ashutosh's iPhone (re-read 2026-10-05)
        ]

        // No FBAdSettings.setAdvertiserTrackingEnabled call here on purpose.
        // Audience Network 6.15.0+ on iOS 17+ ignores that flag and reads
        // ATTrackingManager.trackingAuthorizationStatus itself, so setting it
        // was a deprecated no-op on every device that matters — along with
        // the ordering constraint it implied around MobileAds.start().
        MobileAds.shared.start()

        // ATT must be requested when the app is in the .active state. Calling
        // it from didFinishLaunching is too early — iOS silently no-ops the
        // request and the dialog never shows (App Store review rejected
        // CoopHockey 1.3(14) for exactly this). Defer to didBecomeActive
        // and add a delay so the launch transition completes before the
        // system alert tries to present. 2.0s (was 0.4s) gives Game Center's
        // own sign-in sheet room to appear first, so neither prompt races
        // the other — a collision there was the most likely cause of the
        // 1.3(11) App Store launch-crash rejection, which we could not
        // reproduce locally.
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

        // 2.0s delay lets the launch transition and any Game Center sign-in
        // sheet finish before UMP/ATT try to present. Prompts that collide
        // can either be silently dropped by UIKit or trigger a presentation
        // assertion — either way they are not worth racing to the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // UMP consent runs BEFORE ATT. In the EEA/UK/Switzerland a
            // Google-certified CMP has to gather GDPR consent or those users
            // can only ever be served non-personalised ads. Everywhere else
            // UMP reports "no form required" and this falls straight through.
            //
            // Ads are only preloaded once both prompts have been answered, so
            // the first request carries the right consent and ATT signals.
            ConsentManager.shared.gather(from: Self.keyWindowRoot()) { [weak self] in
                self?.requestATTThenPreloadAds()
            }
        }
    }

    private func requestATTThenPreloadAds() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                Task { @MainActor in
                    AdManager.shared.preload()
                }
            }
        } else {
            Task { @MainActor in AdManager.shared.preload() }
        }
    }

    /// Root controller of the active scene's key window — where the UMP
    /// consent form presents from. Nothing is covering the UI this early in
    /// launch, so the plain root is the right anchor here.
    private static func keyWindowRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .first?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController
    }
}
