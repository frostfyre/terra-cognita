import SwiftUI

struct MarkdownView: View {
    let file: String
    @State private var markdownContent: String = ""

    var body: some View {
        ScrollView {
            Text(markdownContent)
                .padding()
        }
        .onAppear(perform: loadMarkdown)
    }

    private func loadMarkdown() {
        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let atlasURL = currentDirectoryURL.appendingPathComponent("Data/heritage-vault/heritage-vault")
        let markdownURL = atlasURL.appendingPathComponent(file)

        do {
            self.markdownContent = try String(contentsOf: markdownURL)
        } catch {
            print("Error loading markdown for file \(file): \(error)")
            self.markdownContent = "Could not load content for \(file)"
        }
    }
}
