import SwiftUI

/// Sheet that appears on Create New Vault. Shows the shipped templates
/// grouped by mode; the picked template determines the vault's mode,
/// default node types, era taxonomy, and starter subfolders.
///
/// Picking a template fires `onPick(_:)`, dismisses the sheet, and
/// the host (`GraphView`) then opens the folder picker so the user
/// can choose where the new vault lives on disk.
struct TemplatePickerSheet: View {
    @Binding var isPresented: Bool
    let onPick: (Template) -> Void

    /// Track the highlighted template inside the picker so the user
    /// has visual confirmation before they tap Continue.
    @State private var selectedID: String = Template.defaultTemplate.id

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Mode.allCases) { mode in
                        modeSection(mode)
                    }
                }
                .padding()
            }
            .navigationTitle("New Vault")
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
                            onPick(template)
                        }
                    }
                    .disabled(Template.byID(selectedID) == nil)
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 640,
               minHeight: 480, idealHeight: 620)
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
