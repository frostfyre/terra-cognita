import SwiftUI

/// Sheet that appears on Create New Atlas. Shows the shipped templates
/// grouped by mode; the picked template determines the atlas's mode,
/// default node types, era taxonomy, and starter subfolders.
///
/// Picking a template fires `onPick(_:)`, dismisses the sheet, and
/// the host (`GraphView`) then opens the folder picker so the user
/// can choose where the new atlas lives on disk.
struct TemplatePickerSheet: View {
    @Binding var isPresented: Bool
    /// Fires with the chosen template *and* the optional free-form
    /// description the user typed. When the description is non-empty,
    /// the host (`GraphView`) runs it through the AI capture pipeline
    /// after the atlas is created and loaded, seeding the new atlas
    /// with a starter constellation. Empty description ⇒ classic
    /// "create an empty atlas" behavior.
    let onPick: (Template, String) -> Void

    /// Track the highlighted template inside the picker so the user
    /// has visual confirmation before they tap Continue.
    @State private var selectedID: String = Template.defaultTemplate.id
    /// Optional free-form description of the atlas. If non-empty, the
    /// host runs it through the AI capture pipeline after creation to
    /// seed the new atlas with a starter constellation.
    @State private var description: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Mode.allCases) { mode in
                        modeSection(mode)
                    }
                    descriptionSection
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
                            onPick(template, description)
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
    }

    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("Describe what this atlas is about (optional)")
                    .font(.headline)
            }
            Text("If you write a paragraph, the AI will extract a starter constellation of nodes and links after the atlas is created. Leave blank for an empty atlas.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $description)
                .font(.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("e.g., \"The heritage of Studio Ghibli — directors, collaborators, films, and the methods that shaped them…\"")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
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
