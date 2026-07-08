import SwiftUI

/// Popover anchored to the toolbar music-note badge offering an
/// atlas's author-curated music suggestion. Three actions per the
/// design memo's "librarian whisper" pattern:
///
///   - **Listen** — play the suggestion via `MusicService`, record
///     accept so the suggestion doesn't re-appear for this atlas.
///   - **Pick something else** — for v1, just records decline so the
///     prompt goes away. Full Apple Music browser is a v1.1+ feature.
///   - **No thanks** — record decline; nothing plays.
///
/// All paths dismiss the popover. No sound on the suggestion itself
/// — a chime announcing music is contradictory.
struct MusicSuggestionPopover: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    var body: some View {
        let suggestion = store.config.audio.suggestedMusic
        VStack(alignment: .leading, spacing: 14) {
            if let suggestion {
                header(for: suggestion)
                Divider()
                actions(for: suggestion)
            } else {
                Text("No music suggestion for this atlas.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(for suggestion: AtlasConfig.SuggestedMusic) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("This atlas suggests…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestion.displayName)
                    .font(.headline)
                    .lineLimit(2)
                if let attribution = suggestion.attribution, !attribution.isEmpty {
                    Text(attribution)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(for suggestion: AtlasConfig.SuggestedMusic) -> some View {
        VStack(spacing: 8) {
            Button {
                accept(suggestion)
            } label: {
                Label("Listen", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .controlSize(.regular)

            Button {
                decline()
            } label: {
                Text("Not now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .controlSize(.regular)
        }
    }

    // MARK: - Actions

    private func accept(_ suggestion: AtlasConfig.SuggestedMusic) {
        MusicSuggestion.recordAccept(for: store)
        isPresented = false
        Task {
            let result = await MusicService.shared.play(suggestion)
            // Best-effort — surfacing errors as a toast/banner is
            // future polish; for v1 if playback fails the suggestion
            // simply doesn't start and the user can re-try later.
            _ = result
        }
    }

    private func decline() {
        MusicSuggestion.recordDecline(for: store)
        isPresented = false
    }
}
