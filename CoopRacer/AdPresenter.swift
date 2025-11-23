import SwiftUI
import UIKit

/// A stable UIKit view controller we can always present from.
/// Embed this somewhere high in your SwiftUI tree (e.g., HomeView background).
struct AdPresenter: UIViewControllerRepresentable {
    static weak var holder: UIViewController?

    // MARK: - Coordinator listens for ad notifications and manages BGM

    final class Coordinator: NSObject {
        override init() {
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(adWillPresent),
                name: .adWillPresent,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(adDidDismiss),
                name: .adDidDismiss,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func adWillPresent(_ notification: Notification) {
            Task { @MainActor in
                // 🔇 Hard-mute background music whenever an interstitial appears
                BGM.shared.setVolume(0.0, fadeDuration: 0.15)
            }
        }

        @objc private func adDidDismiss(_ notification: Notification) {
            Task { @MainActor in
                // 🎵 Only bring BGM back if music is actually enabled in Settings
                if SettingsStore.shared.musicEnabled {
                    BGM.shared.setVolume(0.20, fadeDuration: 0.20)
                } else {
                    BGM.shared.setVolume(0.0, fadeDuration: 0.0)
                }
            }
        }
    }

    // MARK: - UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        AdPresenter.holder = vc

        // Ensure coordinator starts listening
        _ = context.coordinator

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Nothing to update
    }
}
