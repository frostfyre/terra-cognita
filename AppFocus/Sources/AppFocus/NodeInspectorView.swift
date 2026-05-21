import SwiftUI

struct NodeInspectorView: View {
    let node: Node

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(node.label).font(.title2).bold()
                if let file = node.filePath {
                    MarkdownView(file: file)
                        .frame(maxHeight: 320)
                } else if let markdown = node.markdownContent {
                    ScrollView {
                        Text(.init(markdown))
                            .padding(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 320)
                }
                Divider()
                metadataSection
                // Placeholder for inbound/outbound links
                Text("Links and relationship details will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Metadata").font(.headline)
            ForEach(node.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.caption)
                }
            }
        }
    }
}

#Preview {
    NodeInspectorView(node: Node(id: "sample", label: "Sample Node", attributes: ["type": "person", "era": "bridge"], filePath: nil, markdownContent: nil))
}
