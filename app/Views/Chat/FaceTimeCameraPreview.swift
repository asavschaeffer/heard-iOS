import SwiftUI

struct FaceTimeCameraPreview: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var cameraService = CameraService()

    var body: some View {
        ZStack {
            if cameraService.isCameraReady {
                GeometryReader { geometry in
                    CameraPreviewView(cameraService: cameraService)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else if !cameraService.isAuthorized {
                VStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("Camera access needed")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Enable camera access in Settings to show your video.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.9))
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onDisappear {
            cameraService.stopSession()
            cameraService.stopVideoFrameStreaming()
            cameraService.clearVideoFrameHandler()
            viewModel.stopVideoStreaming()
        }
        .onAppear {
            viewModel.startVideoStreaming(with: cameraService)
        }
    }
}
