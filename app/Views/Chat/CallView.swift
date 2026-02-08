import SwiftUI

struct CallView: View {
    @ObservedObject var viewModel: ChatViewModel
    let style: CallPresentationStyle
    @Environment(\.dismiss) private var dismiss
    let onMinimize: (() -> Void)?
    let onToggleVideo: (() -> Void)?
    let onAddAttachment: (() -> Void)?
    
    init(
        viewModel: ChatViewModel,
        style: CallPresentationStyle,
        onMinimize: (() -> Void)? = nil,
        onToggleVideo: (() -> Void)? = nil,
        onAddAttachment: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.style = style
        self.onMinimize = onMinimize
        self.onToggleVideo = onToggleVideo
        self.onAddAttachment = onAddAttachment
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

            VStack(spacing: 6) {
                Text("Heard, Chef")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                if viewModel.connectionState == .connected {
                    Text(viewModel.callDurationText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    HStack(spacing: 6) {
                        if showsProgress {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white.opacity(0.8))
                                .scaleEffect(0.8)
                        }

                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))

                        if showsDots {
                            CallStatusDots()
                        }
                    }
                }
            }
            .padding(.top, 12)

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 180, height: 180)
                    .scaleEffect(viewModel.callState.isSpeaking ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(), value: viewModel.callState.isSpeaking)

                Image("app-icon-template")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 90)
            }

            Spacer()

            CallControlsView(
                viewModel: viewModel,
                isVideoActive: viewModel.callState.isVideoStreaming,
                onToggleVideo: { onToggleVideo?() },
                onAddAttachment: { onAddAttachment?() }
            ) {
                viewModel.stopVoiceSession()
            }
            .padding(.bottom, 28)
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

    private var statusText: String {
        switch viewModel.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "Reconnecting…"
        case .error:
            return "Connection issue"
        }
    }

    private var showsProgress: Bool {
        viewModel.connectionState != .connected
    }

    private var showsDots: Bool {
        switch viewModel.connectionState {
        case .connecting, .disconnected:
            return true
        case .connected, .error:
            return false
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

private struct CallStatusDots: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animate ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

struct CallOverlayView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onMinimize: () -> Void
    let onToggleVideo: (() -> Void)?
    let onAddAttachment: (() -> Void)?
    
    var body: some View {
        CallView(
            viewModel: viewModel,
            style: .translucentOverlay,
            onMinimize: onMinimize,
            onToggleVideo: onToggleVideo,
            onAddAttachment: onAddAttachment
        )
    }
}
