import Foundation

public struct VoiceCallUIState: Equatable {
    public var isPresented = false
    public var isListening = false
    public var isSpeaking = false
    public var audioLevel: Float = 0.0
    public var isVideoStreaming = false
    public var videoFrameInterval: TimeInterval = 0.2
    public var isMicrophoneMuted = false
    public var isSpeakerPreferred = true
    public var pendingVoiceStart = false
    public var captureStartedFromCallKit = false
    public var useVoiceProcessingInput = true
    public var isCaptureRunning = false
    public var isPlaybackRunning = false

    public init() {}
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
