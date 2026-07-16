import SwiftUI

/// Paywall for the one-and-only in-app purchase: Terra Cognita Pro,
/// which unlocks the Metal ("bolt") renderer. Presented from the PRO
/// toolbar badge when the user isn't entitled. Mirrors `AboutSheet`'s
/// structure (NavigationStack + grouped Form + Done toolbar) so it
/// reads like the rest of the app's modals.
///
/// Honors the DESIGN.md guardrail: Pro gates *compute* (the renderer),
/// never the atlas itself — the copy says so explicitly, and the free
/// Canvas renderer stays fully usable at any graph size.
struct PaywallSheet: View {
    @ObservedObject var entitlements: EntitlementStore
    @Binding var isPresented: Bool

    private var priceLabel: String {
        entitlements.product?.displayPrice ?? "$4.99"
    }

    var body: some View {
        NavigationStack {
            Form {
                identityHeader
                unlockSection
                if let error = entitlements.lastError {
                    Section { Text(error).font(.callout).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Terra Cognita Pro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
            .onAppear {
                // Don't resurface a stale outcome from a previous visit.
                entitlements.restoreStatus = nil
                entitlements.lastError = nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 480, idealHeight: 560)
        #endif
    }

    // MARK: - Sections

    private var identityHeader: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow)
                Text("Pro Renderer")
                    .font(.title2.weight(.semibold))
                Text("Unlock the Metal renderer for an order-of-magnitude fps gain on large atlases. The full atlas stays usable on the free Canvas renderer at any size — Pro speeds up the view, it never gates your data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    /// True once StoreKit has handed us the product. False means the
    /// App Store didn't return it (offline, or the product isn't live
    /// yet) — in which case we disable the buy button rather than let it
    /// silently no-op.
    private var productAvailable: Bool { entitlements.product != nil }

    private var unlockSection: some View {
        Section {
            Button {
                Task { await entitlements.purchase() }
            } label: {
                HStack {
                    Spacer()
                    if entitlements.purchaseInFlight {
                        ProgressView()
                    } else if entitlements.isPro {
                        Label("Pro Unlocked", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                    } else if !productAvailable {
                        Text("Currently unavailable")
                            .fontWeight(.semibold)
                    } else {
                        Text("Unlock Pro — \(priceLabel)")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(entitlements.isPro ? .green : .accentColor)
            .disabled(entitlements.purchaseInFlight || entitlements.isPro || !productAvailable)
            .listRowBackground(Color.clear)

            Button {
                Task { await entitlements.restore() }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                    Spacer()
                    if entitlements.restoreInFlight {
                        ProgressView()
                    }
                }
            }
            .disabled(entitlements.purchaseInFlight || entitlements.restoreInFlight)

            if let status = entitlements.restoreStatus {
                Label(status, systemImage: entitlements.isPro
                      ? "checkmark.circle.fill" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(entitlements.isPro ? .green : .secondary)
            }
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        if entitlements.isPro {
            return "Pro is active on this device. Tap the PRO badge in the toolbar to switch renderers."
        }
        if !productAvailable {
            return "The App Store is unavailable right now, so Pro can't be purchased here. You can still restore a previous purchase, or try again later."
        }
        return "A one-time purchase. Already bought Pro on another device or reinstalled the app? Tap Restore Purchases."
    }
}
