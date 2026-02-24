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
        VStack(spacing: 0) {
            HStack {
                Button {
                    if style == .translucentOverlay {
                        onMinimize?()
                    } else {
                        if let onMinimize {
                            onMinimize()
                        } else {
                            dismiss()
                        }
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
        .background(backgroundView)
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
        .onAppear {
            viewModel.startVoiceSession()
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
                    colors: [Color(red: 0.11, green: 0.11, blue: 0.118), .black],
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

    var body: some View {
        CallView(
            viewModel: viewModel,
            style: .translucentOverlay,
            onMinimize: onMinimize,
            onToggleVideo: onToggleVideo
        )
    }
}
