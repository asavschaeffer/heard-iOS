import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

struct DocumentPicker: UIViewControllerRepresentable {
    let allowedTypes: [UTType]
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

struct CameraCapturePicker: UIViewControllerRepresentable {
    let allowVideo: Bool
    let libraryRequestID: UUID?
    let onPick: (UIImage?, URL?) -> Void
    let onError: ((String) -> Void)?

    init(
        allowVideo: Bool = true,
        libraryRequestID: UUID? = nil,
        onPick: @escaping (UIImage?, URL?) -> Void,
        onError: ((String) -> Void)? = nil
    ) {
        self.allowVideo = allowVideo
        self.libraryRequestID = libraryRequestID
        self.onPick = onPick
        self.onError = onError
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = allowVideo
            ? [UTType.image.identifier, UTType.movie.identifier]
            : [UTType.image.identifier]
        if allowVideo {
            picker.videoQuality = .typeHigh
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.presentLibraryIfNeeded(
            from: uiViewController,
            requestID: libraryRequestID,
            allowVideo: allowVideo
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onError: onError)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
        let onPick: (UIImage?, URL?) -> Void
        let onError: ((String) -> Void)?
        private var lastPresentedLibraryRequestID: UUID?

        init(onPick: @escaping (UIImage?, URL?) -> Void, onError: ((String) -> Void)?) {
            self.onPick = onPick
            self.onError = onError
        }

        func presentLibraryIfNeeded(from picker: UIImagePickerController, requestID: UUID?, allowVideo: Bool) {
            guard let requestID, requestID != lastPresentedLibraryRequestID else { return }
            guard picker.presentedViewController == nil else { return }

            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.selectionLimit = 1
            configuration.filter = allowVideo ? .any(of: [.images, .videos]) : .images

            let controller = PHPickerViewController(configuration: configuration)
            controller.delegate = self
            picker.present(controller, animated: true)
            lastPresentedLibraryRequestID = requestID
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let url = info[.mediaURL] as? URL
            onPick(image, url)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil, nil)
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else { return }
            let provider = result.itemProvider

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [onPick, onError] object, error in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage {
                            onPick(image, nil)
                        } else if error != nil {
                            onError?("Unable to load selected photo.")
                        }
                    }
                }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [onPick, onError] url, error in
                    guard let url else {
                        DispatchQueue.main.async {
                            if error != nil {
                                onError?("Unable to load selected video.")
                            }
                        }
                        return
                    }

                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)

                    do {
                        if FileManager.default.fileExists(atPath: tempURL.path) {
                            try FileManager.default.removeItem(at: tempURL)
                        }
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        DispatchQueue.main.async {
                            onPick(nil, tempURL)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            onError?("Unable to prepare selected video.")
                        }
                    }
                }
                return
            }

            onError?("Unsupported selection.")
        }
    }
}

struct CameraCaptureFlowView: View {
    let allowVideo: Bool
    let onPick: (UIImage?, URL?) -> Void
    let onError: ((String) -> Void)?
    @State private var libraryRequestID: UUID?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CameraCapturePicker(
                allowVideo: allowVideo,
                libraryRequestID: libraryRequestID,
                onPick: onPick,
                onError: onError
            )
                .ignoresSafeArea()

            Button {
                libraryRequestID = UUID()
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Color.black.opacity(0.42), in: Circle())
            }
            .padding(.leading, 24)
            .padding(.bottom, 112)
            .accessibilityIdentifier("chat.camera.openLibraryButton")
        }
    }
}
