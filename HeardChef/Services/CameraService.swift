import Foundation
import AVFoundation
import UIKit
import SwiftUI

// MARK: - Camera Service

class CameraService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var isCameraReady = false
    @Published var capturedImage: UIImage?
    @Published var error: CameraError?

    // MARK: - Properties

    private let captureSession = AVCaptureSession()
    private var videoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var photoContinuation: CheckedContinuation<UIImage?, Error>?

    // MARK: - Initialization

    override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupCamera()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }

        case .denied, .restricted:
            isAuthorized = false
            error = .accessDenied

        @unknown default:
            isAuthorized = false
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession.beginConfiguration()

        // Input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            error = .cameraUnavailable
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Output
        let photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            videoOutput = photoOutput
        }

        captureSession.commitConfiguration()

        isCameraReady = true
    }

    // MARK: - Preview Layer

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existing = previewLayer {
            return existing
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }

    // MARK: - Session Control

    func startSession() {
        guard !captureSession.isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func stopSession() {
        guard captureSession.isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() async throws -> UIImage? {
        guard let videoOutput = videoOutput else {
            throw CameraError.captureError
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            videoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Image Processing

    func processImageForGemini(_ image: UIImage, maxSize: CGSize = CGSize(width: 1024, height: 1024)) -> Data? {
        // Resize if needed
        let resized = resizeImage(image, maxSize: maxSize)

        // Convert to JPEG with moderate compression
        return resized.jpegData(compressionQuality: 0.8)
    }

    private func resizeImage(_ image: UIImage, maxSize: CGSize) -> UIImage {
        let ratio = min(maxSize.width / image.size.width, maxSize.height / image.size.height)

        if ratio >= 1 {
            return image
        }

        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()

        return resized
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            photoContinuation?.resume(throwing: CameraError.captureError)
            photoContinuation = nil
            return
        }

        capturedImage = image
        photoContinuation?.resume(returning: image)
        photoContinuation = nil
    }
}

// MARK: - Camera Error

enum CameraError: LocalizedError {
    case accessDenied
    case cameraUnavailable
    case captureError

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Camera access denied. Please enable in Settings."
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .captureError:
            return "Failed to capture photo."
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let cameraService: CameraService

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let previewLayer = cameraService.getPreviewLayer()
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        cameraService.startSession()

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Session will be stopped when view is removed
    }
}

// MARK: - Full Camera View

struct FullCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraService = CameraService()

    let mode: CaptureMode
    let onCapture: (UIImage, Data) -> Void

    enum CaptureMode {
        case receipt
        case groceries
    }

    @State private var isProcessing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraService.isCameraReady {
                GeometryReader { geometry in
                    CameraPreviewView(cameraService: cameraService)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else if !cameraService.isAuthorized {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.5))

                    Text("Camera Access Required")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Please enable camera access in Settings to scan items.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Overlay UI
            VStack {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()

                    Text(mode == .receipt ? "Scan Receipt" : "Scan Groceries")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    // Placeholder for symmetry
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.clear)
                }
                .padding()

                Spacer()

                // Guide overlay
                if mode == .receipt {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 280, height: 400)
                        .overlay {
                            Text("Position receipt here")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .offset(y: 180)
                        }
                }

                Spacer()

                // Capture button
                Button {
                    capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 70, height: 70)

                        Circle()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 3)
                            .frame(width: 78, height: 78)

                        if isProcessing {
                            ProgressView()
                                .tint(.gray)
                        }
                    }
                }
                .disabled(isProcessing || !cameraService.isCameraReady)
                .padding(.bottom, 40)
            }
        }
        .onDisappear {
            cameraService.stopSession()
        }
    }

    private func capturePhoto() {
        isProcessing = true

        Task {
            do {
                if let image = try await cameraService.capturePhoto(),
                   let imageData = cameraService.processImageForGemini(image) {
                    onCapture(image, imageData)
                    dismiss()
                }
            } catch {
                print("Capture error: \(error)")
            }

            isProcessing = false
        }
    }
}

// MARK: - Image Picker (Alternative)

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
