import UIKit
import GoogleMobileAds
import AVFAudio

final class AppDelegate: NSObject, UIApplicationDelegate {
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

        // 2) (your existing lines)
        let ads = MobileAds.shared
        ads.start()
        AdManager.shared.preload()

        return true
    }
}
