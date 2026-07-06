import Foundation
import StoreKit
import CryptoKit

/// Owns the app's single "Pro" entitlement — the gate for the Metal
/// ("bolt") renderer. Pro is unlocked by either of two independent
/// sources, OR'd together in `isPro`:
///
///   1. A verified StoreKit 2 purchase (the $4.99 non-consumable, or an
///      App Store promo-code redemption — both arrive through the same
///      `Transaction` pipeline). Validated on-device via StoreKit's JWS
///      signature check; we only ever trust `.verified` results.
///   2. A signed *grant token* (CryptoKit Ed25519) minted offline by the
///      developer. Lets us comp Pro to press / testers / friends, with an
///      optional expiry so a grant can time out. The app embeds only the
///      public key and verifies the signature locally — no backend.
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

    /// Ed25519 public key (raw representation, base64) used to verify
    /// signed Pro grant tokens. Empty until you run
    /// `swift scripts/mint_pro_grant.swift keygen` once and paste the
    /// printed public key here. While empty, token redemption is disabled
    /// — purchases and App Store promo codes still work.
    static let grantPublicKeyBase64 = "dKBwix4Kumq8r/oI6+DW5jdbZ9WtJP7YAsOOBKU9rKg="

    /// UserDefaults key holding the redeemed grant token. Storage location
    /// is non-security-critical: the token is signature-protected, so a
    /// user can delete their own grant but cannot forge or extend one.
    /// (Keychain is a future hardening if grants ever carry more weight.)
    private static let grantDefaultsKey = "proGrantToken"

    /// A verified, non-revoked StoreKit entitlement is present.
    @Published public private(set) var storeKitEntitled = false
    /// A valid (signature-checked, unexpired) grant token is present.
    @Published public private(set) var grantActive = false
    /// The loaded product — drives the paywall's price label.
    @Published public private(set) var product: Product?
    /// A purchase round-trip is in flight (disables the buy button).
    @Published public private(set) var purchaseInFlight = false
    /// An `AppStore.sync()` restore is in flight (spins the restore row).
    @Published public private(set) var restoreInFlight = false
    /// User-facing error from the last purchase / restore / redeem.
    @Published public var lastError: String?
    /// Non-error outcome of the last restore ("restored" / "nothing to
    /// restore"). Restore must never finish silently — App Review and
    /// users both need to see that the tap did something.
    @Published public var restoreStatus: String?

    /// The gate. OR of a verified StoreKit entitlement and a valid grant.
    /// Views observing the store re-render when either source changes.
    public var isPro: Bool { storeKitEntitled || grantActive }

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
        refreshGrant()
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
            throw GrantError.unverified
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Signed grant tokens

    /// Redeem a bare grant token. Returns true iff it verified and is
    /// unexpired (and is now active).
    @discardableResult
    public func redeem(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = verify(trimmed) else {
            lastError = Self.grantPublicKeyBase64.isEmpty
                ? "Code redemption isn't configured in this build."
                : "That code isn't valid."
            return false
        }
        if let exp = payload.exp, exp <= Date() {
            lastError = "That code has expired."
            return false
        }
        lastError = nil
        UserDefaults.standard.set(trimmed, forKey: Self.grantDefaultsKey)
        refreshGrant()
        return grantActive
    }

    /// Redeem from a `terracognita://redeem?token=…` deep link.
    @discardableResult
    public func redeem(url: URL) -> Bool {
        guard url.scheme == "terracognita", url.host == "redeem",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "token" })?.value
        else { return false }
        return redeem(token)
    }

    /// Re-evaluate the stored grant (signature + expiry). Clears an
    /// expired or invalid token so the UI relocks. Called on init and on
    /// foreground (`scenePhase` → `.active`) so a timed grant lapses
    /// without needing a relaunch.
    public func refreshGrant() {
        guard let token = UserDefaults.standard.string(forKey: Self.grantDefaultsKey),
              let payload = verify(token) else {
            grantActive = false
            return
        }
        if let exp = payload.exp, exp <= Date() {
            UserDefaults.standard.removeObject(forKey: Self.grantDefaultsKey)
            grantActive = false
            return
        }
        grantActive = true
    }

    /// Verify a token's signature against the embedded public key and
    /// decode its payload. Returns nil on any failure (bad format, bad
    /// signature, or no key configured). Does NOT check expiry — callers
    /// inspect `payload.exp` so they can give a precise "expired" message.
    private func verify(_ token: String) -> GrantPayload? {
        guard !Self.grantPublicKeyBase64.isEmpty,
              let keyData = Data(base64Encoded: Self.grantPublicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return nil }

        let parts = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payloadData = Self.base64urlDecode(String(parts[0])),
              let signature = Self.base64urlDecode(String(parts[1])),
              publicKey.isValidSignature(signature, for: payloadData),
              let payload = try? JSONDecoder().decode(GrantPayload.self, from: payloadData)
        else { return nil }
        return payload
    }

    private struct GrantPayload: Decodable {
        let id: String
        /// Optional expiry as a Date (decoded from unix seconds; absent = permanent).
        let exp: Date?

        private enum CodingKeys: String, CodingKey { case id, exp }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            if let seconds = try c.decodeIfPresent(TimeInterval.self, forKey: .exp) {
                exp = Date(timeIntervalSince1970: seconds)
            } else {
                exp = nil
            }
        }
    }

    private enum GrantError: Error { case unverified }

    /// Decode base64url (no padding) → Data. Mirrors the encoding the
    /// minting script (`scripts/mint_pro_grant.swift`) emits.
    static func base64urlDecode(_ s: String) -> Data? {
        var str = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        let remainder = str.count % 4
        if remainder != 0 { str += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: str)
    }
}
