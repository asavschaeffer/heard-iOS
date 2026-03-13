import SwiftUI
import UIKit

struct CallControlsView: View {
    @ObservedObject var viewModel: ChatViewModel
    let isVideoActive: Bool
    let onToggleVideo: () -> Void
    let onEnd: () -> Void

    @State private var endCallTrigger = false

    private var isConnected: Bool { viewModel.connectionState == .connected }

    var body: some View {
        HStack(spacing: 20) {
            // Mute
            CallControlButton(
                systemImage: viewModel.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill",
                style: viewModel.isMicrophoneMuted ? .activeToggle : .default,
                isEnabled: isConnected
            ) {
                viewModel.toggleMute()
            }

            // Video
            CallControlButton(
                systemImage: isVideoActive ? "video.slash.fill" : "video.fill",
                style: isVideoActive ? .default : .default,
                isEnabled: isConnected
            ) {
                onToggleVideo()
            }

            // End Call
            CallControlButton(
                systemImage: "phone.down.fill",
                style: .destructive,
                isEnabled: true
            ) {
                endCallTrigger.toggle()
                onEnd()
            }

            // Speaker
            CallControlButton(
                systemImage: viewModel.isSpeakerPreferred ? "speaker.wave.3.fill" : "speaker.slash.fill",
                style: viewModel.isSpeakerPreferred ? .activeToggle : .default,
                isEnabled: isConnected
            ) {
                viewModel.toggleSpeaker()
            }

            // Route
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 50, height: 50)
                AudioRoutePickerView(
                    activeTintColor: .white,
                    tintColor: .white.withAlphaComponent(0.8)
                )
                    .frame(width: 50, height: 50)
            }
            .opacity(isConnected ? 1.0 : 0.6)
        }
        .sensoryFeedback(.selection, trigger: viewModel.isMicrophoneMuted)
        .sensoryFeedback(.selection, trigger: isVideoActive)
        .sensoryFeedback(.selection, trigger: viewModel.isSpeakerPreferred)
        .sensoryFeedback(.impact, trigger: endCallTrigger)
    }
}

private enum CallControlStyle {
    case `default`
    case activeToggle
    case destructive

    var background: Color {
        switch self {
        case .default: return Color.white.opacity(0.25)
        case .activeToggle: return .white
        case .destructive: return .red
        }
    }

    var foreground: Color {
        switch self {
        case .default: return .white
        case .activeToggle: return .black
        case .destructive: return .white
        }
    }
}

private struct CallControlButton: View {
    let systemImage: String
    let style: CallControlStyle
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Circle()
                .fill(style.background)
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(style.foreground)
                )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}
