import SwiftUI

struct CallView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    let onMinimize: () -> Void

    var body: some View {
        Group {
            if viewModel.callState.isVideoStreaming {
                faceTimeLayout
            } else {
                callingLayout
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.callState.isVideoStreaming)
        .onAppear {
            viewModel.startVoiceSession()
        }
    }

    // MARK: - Calling Layout (audio-only)

    private var callingLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onMinimize() } label: {
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
                onToggleVideo: { viewModel.toggleVideoFromCallView() }
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
            Color.black.ignoresSafeArea()

            FaceTimeCameraPreview(viewModel: viewModel)
                .ignoresSafeArea()

            // Top-left chevron
            VStack {
                HStack {
                    Button { onMinimize() } label: {
                        Image(systemName: "chevron.down")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 12)
                Spacer()
            }

            // Bottom-right vertical button stack
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        FaceTimeButton(
                            systemImage: "phone.fill"
                        ) {
                            viewModel.toggleVideoFromCallView()
                        }

                        FaceTimeButton(
                            systemImage: viewModel.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill"
                        ) {
                            viewModel.toggleMute()
                        }

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
        } else {
            HStack(spacing: 6) {
                if viewModel.connectionState != .connected {
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

    private var statusText: String {
        switch viewModel.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Reconnecting…"
        case .error: "Connection issue"
        }
    }

    private var showsDots: Bool {
        switch viewModel.connectionState {
        case .connecting, .disconnected: true
        case .connected, .error: false
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
