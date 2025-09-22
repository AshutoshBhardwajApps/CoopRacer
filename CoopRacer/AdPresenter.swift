import SwiftUI
import UIKit

/// A stable UIKit view controller we can always present from.
/// Embed this somewhere high in your SwiftUI tree (e.g., ContentView background).
struct AdPresenter: UIViewControllerRepresentable {
    static weak var holder: UIViewController?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        AdPresenter.holder = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}
