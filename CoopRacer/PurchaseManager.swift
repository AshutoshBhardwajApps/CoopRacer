//
//  PurchaseManager.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-11-19.
//

import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    /// Must match the non-consumable product ID you create in App Store Connect
    private let removeAdsProductID = "coopracer.removeads"

    @Published var removeAdsProduct: Product?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// Mirrors SettingsStore so UI & ad logic stay in sync
    @Published var hasRemovedAds: Bool {
        didSet {
            SettingsStore.shared.hasRemovedAds = hasRemovedAds
        }
    }

    private init() {
        self.hasRemovedAds = SettingsStore.shared.hasRemovedAds
    }

    // MARK: - Product loading

    func loadProducts() async {
        // Only load once per launch unless you want to refresh
        guard removeAdsProduct == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [removeAdsProductID])
            removeAdsProduct = products.first
        } catch {
            print("IAP load error: \(error)")
            errorMessage = "Unable to load purchase options. Please try again later."
        }
    }

    // MARK: - Purchase

    func buyRemoveAds() async {
        errorMessage = nil

        // Already unlocked
        if hasRemovedAds { return }

        // Ensure we have a product
        if removeAdsProduct == nil {
            do {
                let products = try await Product.products(for: [removeAdsProductID])
                removeAdsProduct = products.first
            } catch {
                print("IAP reload error: \(error)")
            }
        }

        guard let product = removeAdsProduct else {
            errorMessage = "Purchase not available yet. Check your connection and try again."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                try await handle(transactionVerification: verificationResult)

            case .userCancelled:
                // User backed out → no error shown
                break

            case .pending:
                errorMessage = "Purchase is pending approval."

            @unknown default:
                break
            }
        } catch {
            print("Purchase error: \(error)")
            errorMessage = "Purchase failed. Please try again."
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        errorMessage = nil
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

            if !restoredSomething && !hasRemovedAds {
                errorMessage = "No purchases to restore."
            }
        } catch {
            print("Restore error: \(error)")
            errorMessage = "Could not restore purchases."
        }
    }

    // MARK: - Transaction handling

    private func handle(transactionVerification: VerificationResult<Transaction>) async throws {
        switch transactionVerification {
        case .unverified(_, let error):
            // Can log this; we don't unlock on unverified
            print("Unverified transaction: \(String(describing: error))")

        case .verified(let transaction):
            // Only care about our remove-ads SKU
            if transaction.productID == removeAdsProductID {
                hasRemovedAds = true
            }
            // Always finish
            await transaction.finish()
        }
    }
}
