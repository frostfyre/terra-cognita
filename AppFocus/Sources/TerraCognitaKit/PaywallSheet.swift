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

    /// Manual grant-token entry. Complements the
    /// `terracognita://redeem?token=…` deep link for press / testers.
    @State private var codeField = ""

    private var priceLabel: String {
        entitlements.product?.displayPrice ?? "$4.99"
    }

    var body: some View {
        NavigationStack {
            Form {
                identityHeader
                unlockSection
                redeemSection
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

    private var unlockSection: some View {
        Section {
            Button {
                Task { await entitlements.purchase() }
            } label: {
                HStack {
                    Spacer()
                    if entitlements.purchaseInFlight {
                        ProgressView()
                    } else {
                        Text("Unlock Pro — \(priceLabel)")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(entitlements.purchaseInFlight || entitlements.isPro)
            .listRowBackground(Color.clear)

            Button("Restore Purchases") {
                Task { await entitlements.restore() }
            }
            .disabled(entitlements.purchaseInFlight)
        } footer: {
            Text("A one-time purchase. Restore re-applies a previous purchase on a new device.")
        }
    }

    private var redeemSection: some View {
        Section {
            DisclosureGroup("Have a code?") {
                TextField("Enter a Pro code", text: $codeField)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Redeem") {
                    if entitlements.redeem(codeField) { codeField = "" }
                }
                .disabled(codeField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
