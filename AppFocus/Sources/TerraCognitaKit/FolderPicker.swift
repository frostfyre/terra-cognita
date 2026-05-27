#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wraps `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`
/// for use inside SwiftUI. We need this on iOS because SwiftUI's
/// `.fileImporter` with `.folder` has been observed to silently no-op
/// when presented from inside a `Menu` button action — common iPhone
/// vault-open flow. UIKit picker doesn't have that race.
///
/// The picked folder URL is delivered as a security-scoped resource:
/// callers must `startAccessingSecurityScopedResource()` before reading
/// and balance it with a stop on the same URL.
struct FolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.folder],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, isPresented: $isPresented)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        @Binding var isPresented: Bool

        init(onPick: @escaping (URL?) -> Void,
             isPresented: Binding<Bool>) {
            self.onPick = onPick
            _isPresented = isPresented
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
            isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
            isPresented = false
        }
    }
}
#endif
