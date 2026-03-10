import Foundation

struct VoiceCallUIState: Equatable {
    var isPresented = false
    var isListening = false
    var isSpeaking = false
    var audioLevel: Float = 0.0
    var isVideoStreaming = false
    var videoFrameInterval: TimeInterval = 0.2
    var isMicrophoneMuted = false
    var isSpeakerPreferred = true
    var pendingVoiceStart = false
    var captureStartedFromCallKit = false
    var useVoiceProcessingInput = true
    var isCaptureRunning = false
    var isPlaybackRunning = false
}

enum VoiceTransportState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var debugLabel: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .error(let message):
            return "error(\(message))"
        }
    }
}
