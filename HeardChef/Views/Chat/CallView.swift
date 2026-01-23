import SwiftUI

struct CallView: View {
    @ObservedObject var viewModel: ChatViewModel
    let style: CallPresentationStyle
    @Environment(\.dismiss) private var dismiss
    let onMinimize: (() -> Void)?
    
    init(viewModel: ChatViewModel, style: CallPresentationStyle, onMinimize: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.style = style
        self.onMinimize = onMinimize
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if style == .translucentOverlay {
                        onMinimize?()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            VStack(spacing: 8) {
                Text("Heard, Chef")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    if viewModel.connectionState != .connected {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white.opacity(0.8))
                            .scaleEffect(0.8)
                    }

                    Text(viewModel.connectionState == .connected ? "Call answered" : "Calling...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.top, 20)

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .scaleEffect(viewModel.callState.isSpeaking ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(), value: viewModel.callState.isSpeaking)

                Image("app-icon-template")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110)
            }

            Spacer()

            CallControlsView(viewModel: viewModel) {
                viewModel.stopVoiceSession()
            }
            .padding(.bottom, 36)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundView)
        .onAppear {
            viewModel.startVoiceSession()
        }
        .onDisappear {
            viewModel.stopVoiceSession()
        }
    }
    
    private var backgroundView: some View {
        Group {
            switch style {
            case .fullScreen:
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            case .translucentOverlay:
                ZStack {
                    FaceTimeCameraPreview(viewModel: viewModel)
                    Color.black.opacity(0.35)
                }
                .ignoresSafeArea()
            case .pictureInPicture:
                Color.clear
            }
        }
    }
}

struct CallOverlayView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onMinimize: () -> Void
    
    var body: some View {
        CallView(viewModel: viewModel, style: .translucentOverlay, onMinimize: onMinimize)
    }
}
