import UIKit
import GoogleMobileAds

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        let ads = MobileAds.shared   // <-- no parentheses
        ads.start()                              // or: ads.start(completionHandler: nil)

        return true
    }
}
