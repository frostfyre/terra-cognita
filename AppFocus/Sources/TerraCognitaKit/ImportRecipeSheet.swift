import SwiftUI

/// Three-stage sheet for the Import Recipe flow:
///   1. **Author** — user types natural-language instructions.
///   2. **Review** — the parsed `ImportRecipe` is shown as cards.
///      User can adjust per-rule values inline or back to step 1.
///   3. **Outcome** — after the user picks source + destination
///      folders, the executor runs and reports counts.
///
/// Per DESIGN.md: AI interprets, the importer executes
/// deterministically. The Review stage is where the user vetoes /
/// edits before any file is written.
struct ImportRecipeSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool

    private enum Stage {
        case author
        case interpreting
        case review(ImportRecipe)
        case running
        case done(RecipeExecutor.Outcome, destination: URL)
        case failure(String)
    }

    @State private var stage: Stage = .author
    @State private var instructions: String = ""

    var body: some View {
        NavigationStack {
            stageContent
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("Import Recipe")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
        }
        .frame(minWidth: 540, idealWidth: 640,
               minHeight: 460, idealHeight: 600)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .author:        authorPane
        case .interpreting:  interpretingPane
        case .review(let r): reviewPane(r)
        case .running:       runningPane
        case .done(let o, _): donePane(o)
        case .failure(let m): failurePane(m)
        }
    }

    // MARK: - Stage 1: Author

    private var authorPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe what to import")
                .font(.headline)
            Text("Tell Terra Cognita in plain English what kinds of files become which nodes, and how to link them. Examples:\n\n• Import a folder. Texture nodes (orange) for every .png, asset nodes (blue) for every .asset. Link textures to assets where the texture name appears in the asset file.\n\n• Walk a Swift repo. One node per .swift file, type 'class', color cyan. Link by name reference in imports.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $instructions)
                .font(.body)
                .frame(minHeight: 160)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            if !RecipeInterpreter.isAvailable {
                Label("AI is not available on this device.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button {
                    Task { await interpret() }
                } label: {
                    Label("Interpret", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || !RecipeInterpreter.isAvailable)
            }
        }
    }

    // MARK: - Stage 2: Interpreting

    private var interpretingPane: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Parsing your instructions…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stage 3: Review

    @ViewBuilder
    private func reviewPane(_ recipe: ImportRecipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(recipe.summary, systemImage: "doc.text")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Text("Node types").font(.headline)
                ForEach(recipe.nodeRules) { rule in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(swatch(rule.color))
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rule.typeName).font(.body.weight(.medium))
                            Text("\(rule.filePattern)  ·  label by \(rule.labelStrategy.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.06))
                    )
                }

                if !recipe.edgeRules.isEmpty {
                    Text("Edge rules").font(.headline).padding(.top, 6)
                    ForEach(recipe.edgeRules) { rule in
                        HStack {
                            Text(rule.sourceType)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(rule.targetType)
                            Spacer()
                            Text(rule.strategy.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    }
                }

                HStack {
                    Button("Back") { stage = .author }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        Task { await runRecipe(recipe) }
                    } label: {
                        Label("Pick folder & run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
        }
    }

    private func swatch(_ raw: String) -> Color {
        AtlasConfig.parseColor(raw) ?? .secondary
    }

    // MARK: - Stage 4: Running / Done

    private var runningPane: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Materializing atlas…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func donePane(_ outcome: RecipeExecutor.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Imported", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("\(outcome.totalNodes) node\(outcome.totalNodes == 1 ? "" : "s") created across \(outcome.nodesByType.count) type\(outcome.nodesByType.count == 1 ? "" : "s"); \(outcome.edgesCreated) edge\(outcome.edgesCreated == 1 ? "" : "s").")
                .foregroundStyle(.secondary)
            ForEach(outcome.nodesByType.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                HStack {
                    Text(kv.key).font(.body)
                    Spacer()
                    Text("\(kv.value)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func failurePane(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message).foregroundStyle(.secondary)
            HStack {
                Button("Back") { stage = .author }
                Spacer()
            }
        }
    }

    // MARK: - Stage transitions

    private func interpret() async {
        stage = .interpreting
        do {
            let recipe = try await RecipeInterpreter.interpret(instructions)
            stage = .review(recipe)
        } catch {
            stage = .failure(error.localizedDescription)
        }
    }

    /// Pick source folder, then destination folder, then execute.
    /// Uses the same `FolderPicker` (iOS) / `NSOpenPanel` (macOS)
    /// affordances the rest of the app uses. For Phase 3 first cut
    /// the two pickers run sequentially via platform-native dialogs.
    private func runRecipe(_ recipe: ImportRecipe) async {
        #if os(macOS)
        guard let source = await pickFolder(prompt: "Pick the SOURCE folder to import from") else { return }
        guard let destination = await pickFolder(prompt: "Pick a DESTINATION folder for the new atlas") else { return }
        stage = .running
        do {
            let outcome = try RecipeExecutor.execute(recipe,
                                                     source: source,
                                                     destination: destination)
            stage = .done(outcome, destination: destination)
            // Open the new atlas automatically.
            store.load(from: destination)
        } catch {
            stage = .failure(error.localizedDescription)
        }
        #else
        // iOS: pickers are async via sheets. Phase 3 first cut just
        // surfaces a message; full iOS flow lands with the
        // `FolderPicker` wiring in a follow-up.
        stage = .failure("Folder pickers for Import Recipe on iOS are coming in a follow-up commit. macOS works today.")
        #endif
    }

    #if os(macOS)
    @MainActor
    private func pickFolder(prompt: String) async -> URL? {
        await withCheckedContinuation { cont in
            let panel = NSOpenPanel()
            panel.message = prompt
            panel.prompt = "Choose"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.begin { response in
                cont.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
    #endif
}

#if canImport(AppKit)
import AppKit
#endif
