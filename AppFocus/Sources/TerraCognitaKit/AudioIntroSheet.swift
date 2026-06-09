import SwiftUI

/// First-launch introduction to the app's audio identity. Shown once
/// per Apple ID after the cold-start splash dissolves, gated on
/// `AudioUserPreference.introSeen`. Two outcomes:
///
///   - **Hear it** → sets the global chime opt-in, flips the current
///     atlas's `audio.chimeEnabled`, fires a confirmation chime so
///     the user experiences the sound immediately.
///   - **Not now** → leaves chime off; the user can opt in later via
///     the toolbar speaker control or Atlas Settings → Audio.
///
/// Either choice marks `introSeen = true` so the prompt never
/// auto-presents again.
struct AudioIntroSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "waveform.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 18)

            Text("Terra Cognita has a voice.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

            Text("Selecting a node rings a soft glass-bell chord whose pitches come from the connected node types. The longer you spend in an atlas, the more its shape becomes audible — connections you didn't notice visually surface as patterns in sound.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

            Text("Optional. AirPods spatial audio supported. Always toggleable from the toolbar.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    accept()
                } label: {
                    Text("Hear it")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)

                Button {
                    decline()
                } label: {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)
        #if os(macOS)
        .frame(minHeight: 420, idealHeight: 480)
        #endif
        .background(.regularMaterial)
        .interactiveDismissDisabled()
    }

    // MARK: - Actions

    private func accept() {
        AudioUserPreference.chimeOptIn = true
        AudioUserPreference.introSeen = true
        store.setChimeEnabled(true)
        // Single confirmation chime so the user immediately experiences
        // the sound they just opted into.
        ChimeSonifier.fireLaunchTone(enabled: true)
        isPresented = false
    }

    private func decline() {
        AudioUserPreference.introSeen = true
        // Leave chimeOptIn untouched (defaults false).
        isPresented = false
    }
}
