import SwiftUI

struct CallView: View {
    @ObservedObject var viewModel: ChatViewModel
    let style: CallPresentationStyle
    @Environment(\.dismiss) private var dismiss
    let onMinimize: (() -> Void)?
    let onToggleVideo: (() -> Void)?

    init(
        viewModel: ChatViewModel,
        style: CallPresentationStyle,
        onMinimize: (() -> Void)? = nil,
        onToggleVideo: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.style = style
        self.onMinimize = onMinimize
        self.onToggleVideo = onToggleVideo
    }

    var body: some View {
        Group {
            switch style {
            case .translucentOverlay:
                faceTimeLayout
            case .fullScreen:
                callingLayout
            case .pictureInPicture:
                callingLayout
            }
        }
        .onAppear {
            viewModel.startVoiceSession()
        }
    }

    // MARK: - Calling Layout (audio-only fullscreen)

    private var callingLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let onMinimize {
                        onMinimize()
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

                callStatusLabel
            }
            .padding(.top, 12)

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .shadow(color: viewModel.callState.isSpeaking ? .white.opacity(0.15) : .clear, radius: 20)
                    .scaleEffect(viewModel.callState.isSpeaking ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(), value: viewModel.callState.isSpeaking)

                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.11, blue: 0.118), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom) {
            CallControlsView(
                viewModel: viewModel,
                isVideoActive: viewModel.callState.isVideoStreaming,
                onToggleVideo: { onToggleVideo?() }
            ) {
                viewModel.stopVoiceSession()
            }
            .padding(.bottom, 12)
            .padding(.horizontal)
        }
    }

    // MARK: - FaceTime Layout (video call)

    private var faceTimeLayout: some View {
        ZStack {
            // Opaque base so chat doesn't bleed through
            Color.black.ignoresSafeArea()

            // Full-screen camera feed
            FaceTimeCameraPreview(viewModel: viewModel)
                .ignoresSafeArea()

            // Bottom-right vertical button stack
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        // FaceTime (video toggle)
                        FaceTimeButton(
                            systemImage: viewModel.callState.isVideoStreaming ? "video.fill" : "video.slash.fill",
                            isActive: viewModel.callState.isVideoStreaming
                        ) {
                            onToggleVideo?()
                        }

                        // Mute
                        FaceTimeButton(
                            systemImage: viewModel.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill",
                            isActive: !viewModel.isMicrophoneMuted
                        ) {
                            viewModel.toggleMute()
                        }

                        // Hang up
                        FaceTimeButton(
                            systemImage: "phone.down.fill",
                            isDestructive: true
                        ) {
                            viewModel.stopVoiceSession()
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 48)
                }
            }
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var callStatusLabel: some View {
        if viewModel.connectionState == .connected {
            Text(viewModel.callDurationText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .shadow(color: .black.opacity(0.3), radius: 2)
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
                    .shadow(color: .black.opacity(0.3), radius: 2)

                if showsDots {
                    CallStatusDots()
                }
            }
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

private struct FaceTimeButton: View {
    let systemImage: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background {
                    if isDestructive {
                        Circle().fill(.red)
                    } else if isActive {
                        Circle().fill(.green)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
        }
    }
}

struct CallOverlayView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onMinimize: () -> Void
    let onToggleVideo: (() -> Void)?

    var body: some View {
        CallView(
            viewModel: viewModel,
            style: .translucentOverlay,
            onMinimize: onMinimize,
            onToggleVideo: onToggleVideo
        )
    }
}
