import SwiftUI

/// Sheet that appears on Create New Atlas. Shows the shipped templates
/// grouped by mode; the picked template determines the atlas's mode,
/// default node types, era taxonomy, and starter subfolders.
///
/// Picking a template fires `onPick(_:)`, dismisses the sheet, and
/// the host (`GraphView`) then opens the folder picker so the user
/// can choose where the new atlas lives on disk.
struct TemplatePickerSheet: View {
    @ObservedObject var store: GraphStore
    @Binding var isPresented: Bool
    /// Fires with the chosen template and the optional starter
    /// constellation the user grew in the Genesis Chat. When the
    /// constellation has nodes, the host (`GraphView`) commits it
    /// via `store.applyConstellation` after the empty atlas finishes
    /// loading. `nil` ⇒ classic "create an empty atlas" behavior.
    let onPick: (Template, Constellation?) -> Void

    /// Track the highlighted template inside the picker so the user
    /// has visual confirmation before they tap Continue.
    @State private var selectedID: String = Template.defaultTemplate.id
    /// Working constellation built up across genesis-chat turns.
    /// Owned by the picker (so it survives chat updates) and handed
    /// to the host on Continue.
    @State private var workingConstellation: Constellation?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Mode.allCases) { mode in
                        modeSection(mode)
                    }
                    genesisSection
                }
                .padding()
            }
            .navigationTitle("New Atlas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        if let template = Template.byID(selectedID) {
                            onPick(template, workingConstellation)
                        }
                    }
                    .disabled(Template.byID(selectedID) == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 640,
               minHeight: 480, idealHeight: 620)
        #endif
        // The Genesis chat starts an async AI task on Send. Disabling
        // interactive dismissal prevents the iOS swipe-to-close from
        // tearing the sheet (and its in-flight task) down mid-extraction.
        // Cancel still works.
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private var genesisSection: some View {
        AtlasGenesisChat(
            store: store,
            constellation: $workingConstellation
        )
        .padding(.top, 8)
    }

    @ViewBuilder
    private func modeSection(_ mode: Mode) -> some View {
        let templates = Template.templates(for: mode)
        if !templates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: mode.systemImage)
                        .foregroundStyle(.tint)
                    Text(mode.displayName)
                        .font(.headline)
                }
                Text(mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(templates) { template in
                    templateRow(template)
                }
            }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: Template) -> some View {
        let selected = template.id == selectedID
        Button {
            selectedID = template.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.systemImage)
                    .imageScale(.large)
                    .frame(width: 28)
                    .foregroundStyle(selected
                                     ? AnyShapeStyle(.tint)
                                     : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.body.weight(.medium))
                    Text(template.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected
                          ? Color.accentColor.opacity(0.10)
                          : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : .clear,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
