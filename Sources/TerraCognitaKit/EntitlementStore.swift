import Foundation
import StoreKit

/// Owns the app's single "Pro" entitlement — the gate for the Metal
/// ("bolt") renderer. Pro is unlocked exclusively by a verified
/// StoreKit 2 purchase (the $4.99 non-consumable; App Store promo /
/// offer codes arrive through the same `Transaction` pipeline).
/// Validated on-device via StoreKit's JWS signature check; we only
/// ever trust `.verified` results.
///
/// Lives as a `@StateObject` on `GraphView` (mirroring `navigation`), so
/// all three app targets pick it up without per-target wiring. The
/// AppStorage `useProRenderer` flag is a *preference* only; the renderer
/// gate ANDs it with `isPro` so a stale `true` can never unlock anything.
@MainActor
public final class EntitlementStore: ObservableObject {
    /// Non-consumable product id. Shared bundle id → one Universal
    /// Purchase across iOS + macOS.
    public static let proProductID = "com.frostfyre.terracognitaatlas.pro"

    /// A verified, non-revoked StoreKit entitlement is present.
    @Published public private(set) var storeKitEntitled = false
    /// The loaded product — drives the paywall's price label.
    @Published public private(set) var product: Product?
    /// A purchase round-trip is in flight (disables the buy button).
    @Published public private(set) var purchaseInFlight = false
    /// An `AppStore.sync()` restore is in flight (spins the restore row).
    @Published public private(set) var restoreInFlight = false
    /// User-facing error from the last purchase / restore.
    @Published public var lastError: String?
    /// Non-error outcome of the last restore ("restored" / "nothing to
    /// restore"). Restore must never finish silently — App Review and
    /// users both need to see that the tap did something.
    @Published public var restoreStatus: String?

    /// The gate. Views observing the store re-render when it changes.
    public var isPro: Bool { storeKitEntitled }

    public init() {
        // Start the transaction listener BEFORE the first await so an
        // update that lands during launch (e.g. an Ask-to-Buy approval,
        // or a purchase made on another device) isn't dropped. The store
        // is app-lifetime, so the unstructured task lives as long as needed.
        Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refreshEntitlements(); await loadProduct() }
    }

    // MARK: - StoreKit

    /// Re-scan current entitlements (the live source of truth) and set
    /// `storeKitEntitled`. Never derive entitlement from a cached flag.
    public func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        storeKitEntitled = entitled
    }

    public func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.proProductID]).first
        } catch {
            lastError = "Couldn't load the Pro product. Check your connection and try again."
        }
    }

    public func purchase() async {
        guard let product else {
            await loadProduct()
            return
        }
        lastError = nil
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                lastError = "Your purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed. \(error.localizedDescription)"
        }
    }

    /// Required by App Review: re-sync with the App Store so a prior
    /// non-consumable purchase re-grants on a fresh install / new device.
    /// Always ends in visible feedback — success, "nothing found", or an
    /// error — never a silent no-op.
    public func restore() async {
        lastError = nil
        restoreStatus = nil
        restoreInFlight = true
        defer { restoreInFlight = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            restoreStatus = storeKitEntitled
                ? "Pro restored. You're all set."
                : "No previous purchase was found for this Apple Account."
        } catch StoreKitError.userCancelled {
            // User dismissed the App Store sign-in sheet — not an error.
        } catch {
            lastError = "Couldn't restore purchases. \(error.localizedDescription)"
        }
    }

    /// Listener path for asynchronous transaction updates (refunds,
    /// Ask-to-Buy approvals, cross-device restores). A refund clears the
    /// entitlement here, relocking the renderer without a relaunch.
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    /// Trust only `.verified` — StoreKit has already checked the JWS
    /// signature chain on-device; an `.unverified` result is treated as
    /// not entitled.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw EntitlementError.unverified
        case .verified(let safe):
            return safe
        }
    }

    private enum EntitlementError: Error { case unverified }
}
