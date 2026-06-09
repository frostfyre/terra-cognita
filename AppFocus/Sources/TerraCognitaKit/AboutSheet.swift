import SwiftUI

/// App-level About screen — identity, version, support link, legal
/// links, contact. Surfaced from the Atlas menu. Lives at the app
/// level (not per-atlas) because everything here is process-global:
/// who made the app, where to support it, where the legal docs live.
struct AboutSheet: View {
    @Binding var isPresented: Bool

    private static let appName = "Terra Cognita"
    private static let tagline = "A Graph-First Semantic Explorer"

    var body: some View {
        NavigationStack {
            Form {
                identityHeader
                aboutSection
                supportSection
                linksSection
                contactSection
                copyrightFooter
            }
            .formStyle(.grouped)
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        // Sized for macOS sheet presentation; iOS uses full-screen sheet
        // and a min width would clip on iPhone.
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 540, idealHeight: 640)
        #endif
    }

    // MARK: - Sections

    private var identityHeader: some View {
        Section {
            VStack(spacing: 8) {
                Text(Self.appName)
                    .font(.title.weight(.semibold))
                Text(Self.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("Terra Cognita treats your atlas of markdown notes as the primary work surface — a navigable, queryable, AI-augmented graph of the people, events, institutions, works, and concepts that shape a life or a project.")
                .font(.callout)
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Link(destination: AppLinks.support) {
                Label("Support Terra Cognita", systemImage: "heart")
            }
            Text("Terra Cognita is free, donation-supported, and source-available under PolyForm Noncommercial. If it's earning a spot in your workflow, a contribution helps keep development going.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var linksSection: some View {
        Section("Links") {
            Link(destination: AppLinks.marketing) {
                Label("terra-cognita.app", systemImage: "globe")
            }
            Link(destination: AppLinks.privacy) {
                Label("Privacy Policy", systemImage: "lock.shield")
            }
            Link(destination: AppLinks.license) {
                Label("License (PolyForm Noncommercial 1.0.0)", systemImage: "doc.text")
            }
        }
    }

    private var contactSection: some View {
        Section("Contact") {
            Link(destination: AppLinks.contact) {
                Label("info@terra-cognita.app", systemImage: "envelope")
            }
        }
    }

    private var copyrightFooter: some View {
        Section {
            Text("© 2026 Frostfyre Studios")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
    }

    /// Pulled from the bundle Info.plist so it auto-tracks the build
    /// number bumped by `scripts/upload_testflight.sh`.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }
}

/// Canonical URLs surfaced in the About sheet (and anywhere else the
/// app needs to link out). All point at `terra-cognita.app` paths so
/// the destination is redirectable — e.g. `/support` can route to
/// Buy Me A Coffee today, Ko-fi tomorrow, GitHub Sponsors after that,
/// all without an app update.
enum AppLinks {
    /// Donation landing — the page on terra-cognita.app that redirects
    /// to whatever channel is currently primary (Buy Me A Coffee as
    /// of 2026-06-08).
    static let support = URL(string: "https://terra-cognita.app/support")!

    /// Public marketing / landing.
    static let marketing = URL(string: "https://terra-cognita.app")!

    /// Privacy policy. Mirrors `Legal/PRIVACY.md`.
    static let privacy = URL(string: "https://terra-cognita.app/privacy")!

    /// PolyForm Noncommercial 1.0.0 canonical text.
    static let license = URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!

    /// Beta + general contact email.
    static let contact = URL(string: "mailto:info@terra-cognita.app")!
}
