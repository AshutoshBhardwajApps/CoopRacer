//
//  PurchaseManager.swift
//  CoopRacer
//

import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    // Use the same ID as SettingsStore
    private let removeAdsProductID = SettingsStore.removeAdsProductID

    @Published private(set) var removeAdsProduct: Product?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    // Mirrors SettingsStore so UI & ad logic stay in sync
    @Published var hasRemovedAds: Bool {
        didSet {
            SettingsStore.shared.hasRemovedAds = hasRemovedAds
        }
    }

    private init() {
        self.hasRemovedAds = SettingsStore.shared.hasRemovedAds
    }

    // MARK: - Product loading

    /// Loads the Remove Ads product once per launch.
    func loadProducts() async {
        guard removeAdsProduct == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [removeAdsProductID])
            removeAdsProduct = products.first
            if removeAdsProduct == nil {
                print("[PurchaseManager] Warning: no product returned for \(removeAdsProductID)")
            }
        } catch {
            // Log, but don't show an error on the Settings screen just for this.
            print("[PurchaseManager] loadProducts error: \(error)")
        }
    }

    // MARK: - Purchase

    func buyRemoveAds() async {
        // Clear any previous error only when the user actively taps "Remove Ads"
        errorMessage = nil

        if hasRemovedAds { return }

        // Ensure we have a product
        if removeAdsProduct == nil {
            do {
                let products = try await Product.products(for: [removeAdsProductID])
                removeAdsProduct = products.first
            } catch {
                print("[PurchaseManager] reload products error: \(error)")
            }
        }

        guard let product = removeAdsProduct else {
            errorMessage = "Purchase not available. Please try again later."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                try await handle(transactionVerification: verification)

            case .userCancelled:
                // User backed out → not a failure; don't show error text.
                break

            case .pending:
                // Ask-to-Buy etc.
                errorMessage = "Purchase is pending approval."

            @unknown default:
                errorMessage = "Purchase failed. Please try again."
            }
        } catch {
            print("[PurchaseManager] purchase error: \(error)")
            errorMessage = "Purchase failed. Please try again."
        }
    }

    // MARK: - Restore

    /// `userInitiated` is true only when the user taps the "Restore Purchases" button.
    /// On app launch we call this with `false` so no red error text is shown.
    func restorePurchases(userInitiated: Bool = false) async {
        if userInitiated {
            errorMessage = nil
        }

        isLoading = true
        defer { isLoading = false }

        var restoredSomething = false

        do {
            for await result in Transaction.currentEntitlements {
                try await handle(transactionVerification: result)

                if case .verified(let transaction) = result,
                   transaction.productID == removeAdsProductID {
                    restoredSomething = true
                }
            }

            if userInitiated {
                if restoredSomething {
                    errorMessage = "Purchases restored on this device."
                } else if !hasRemovedAds {
                    errorMessage = "No purchases to restore."
                }
            }
            // If not userInitiated, stay silent: no error label just from opening Settings.
        } catch {
            print("[PurchaseManager] restore error: \(error)")
            if userInitiated {
                errorMessage = "Could not restore purchases. Please try again."
            }
        }
    }

    // MARK: - Transaction handling

    private func handle(transactionVerification: VerificationResult<Transaction>) async throws {
        switch transactionVerification {
        case .unverified(_, let error):
            print("[PurchaseManager] Unverified transaction: \(String(describing: error))")

        case .verified(let transaction):
            if transaction.productID == removeAdsProductID {
                hasRemovedAds = true
            }
            await transaction.finish()
        }
    }
}
