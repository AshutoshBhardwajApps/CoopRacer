import Foundation
import StoreKit

/// StoreKit 2 Remove Ads purchase, ported from CoopHockey.
@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var localizedPrice: String?

    private var removeAdsProduct: Product?

    private init() {}

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: [SettingsStore.removeAdsProductID])
            removeAdsProduct = fetched.first
            localizedPrice = removeAdsProduct?.displayPrice
        } catch {
            print("[PurchaseManager] loadProducts error: \(error)")
        }
    }

    func buyRemoveAds() async {
        guard let product = removeAdsProduct else {
            errorMessage = "Product not available. Try again later."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    apply(productID: transaction.productID)
                    await transaction.finish()
                }
            case .userCancelled: break
            case .pending: errorMessage = "Purchase pending approval."
            @unknown default: break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result { apply(productID: t.productID) }
        }
    }

    private func apply(productID: String) {
        if productID == SettingsStore.removeAdsProductID {
            SettingsStore.shared.markRemoveAdsPurchased()
        }
    }
}
