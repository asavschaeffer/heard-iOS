import SwiftUI

struct CallControlsView: View {
    @ObservedObject var viewModel: ChatViewModel
    let isVideoActive: Bool
    let onToggleVideo: () -> Void
    let onAddAttachment: () -> Void
    let onEnd: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 28) {
                CallControlButton(
                    title: viewModel.callState.isListening ? "Mute" : "Unmute",
                    systemImage: viewModel.callState.isListening ? "mic.slash.fill" : "mic.fill",
                    background: .white.opacity(0.18),
                    foreground: .white,
                    isEnabled: viewModel.connectionState == .connected
                ) {
                    viewModel.toggleMute()
                }

                VStack(spacing: 8) {
                    AudioRoutePickerView()
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.18), in: Circle())
                    Text("Audio")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .opacity(viewModel.connectionState == .connected ? 1.0 : 0.6)

                CallControlButton(
                    title: isVideoActive ? "Stop Video" : "Video",
                    systemImage: isVideoActive ? "video.slash.fill" : "video.fill",
                    background: .white.opacity(0.18),
                    foreground: .white,
                    isEnabled: viewModel.connectionState == .connected
                ) {
                    onToggleVideo()
                }
            }

            HStack(spacing: 36) {
                CallControlButton(
                    title: "Add",
                    systemImage: "plus",
                    background: .white.opacity(0.18),
                    foreground: .white,
                    isEnabled: true
                ) {
                    onAddAttachment()
                }

                CallControlButton(
                    title: "End",
                    systemImage: "phone.down.fill",
                    background: .red,
                    foreground: .white,
                    isEnabled: true
                ) {
                    onEnd()
                }
            }
        }
    }
}

private struct CallControlButton: View {
    let title: String
    let systemImage: String
    let background: Color
    let foreground: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(background)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.title2)
                            .foregroundStyle(foreground)
                    )
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.5))
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}
