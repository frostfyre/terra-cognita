#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wraps `UIDocumentPickerViewController(forOpeningContentTypes:)` for
/// picking a *file* on iOS. Mirrors `FolderPicker`: SwiftUI's
/// `.fileImporter` has been observed to silently no-op when presented
/// from inside a `Menu` button action (the Atlas menu's "Import
/// GEXF…" flow), so we present a UIKit picker via `.sheet` instead.
///
/// `asCopy: true` hands back a temporary local copy of the picked
/// file, readable without juggling a security-scoped resource — which
/// suits import flows that parse the file immediately.
struct FilePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let contentTypes: [UTType]
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
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
