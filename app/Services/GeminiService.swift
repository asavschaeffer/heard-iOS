import Foundation
import SwiftData
import VoiceCore

// MARK: - Voice Selection

enum GeminiVoice: String, CaseIterable, Identifiable {
    case aoede = "Aoede"       // Bright
    case charon = "Charon"     // Informative
    case fenrir = "Fenrir"     // Excitable
    case kore = "Kore"         // Firm
    case leda = "Leda"         // Youthful
    case orus = "Orus"         // Firm
    case puck = "Puck"         // Upbeat
    case zephyr = "Zephyr"     // Bright

    case achernar = "Achernar" // Soft
    case algenib = "Algenib"   // Gravelly
    case algieba = "Algieba"   // Smooth
    case alnilam = "Alnilam"   // Firm
    case autonoe = "Autonoe"   // Bright
    case callirrhoe = "Callirrhoe" // Smooth
    case despina = "Despina"   // Smooth
    case erinome = "Erinome"   // Clear
    case gacrux = "Gacrux"     // Mature
    case isonoe = "Isonoe"     // Balanced
    case juliet = "Juliet"     // Confident
    case keid = "Keid"         // Breathy
    case koppa = "Koppa"       // Bright
    case laomedeia = "Laomedeia" // Upbeat
    case pulcherrima = "Pulcherrima" // Forward
    case rasalgethi = "Rasalgethi" // Informative
    case rasalhague = "Rasalhague" // Informative
    case sadachbia = "Sadachbia" // Lively
    case sadaltager = "Sadaltager" // Knowledgeable
    case sulafat = "Sulafat"   // Warm
    case umbriel = "Umbriel"   // Easy-going
    case vindemiatrix = "Vindemiatrix" // Gentle

    var id: String { rawValue }

    var description: String {
        switch self {
        case .aoede: "Bright"
        case .charon: "Informative"
        case .fenrir: "Excitable"
        case .kore: "Firm"
        case .leda: "Youthful"
        case .orus: "Firm"
        case .puck: "Upbeat"
        case .zephyr: "Bright"
        case .achernar: "Soft"
        case .algenib: "Gravelly"
        case .algieba: "Smooth"
        case .alnilam: "Firm"
        case .autonoe: "Bright"
        case .callirrhoe: "Smooth"
        case .despina: "Smooth"
        case .erinome: "Clear"
        case .gacrux: "Mature"
        case .isonoe: "Balanced"
        case .juliet: "Confident"
        case .keid: "Breathy"
        case .koppa: "Bright"
        case .laomedeia: "Upbeat"
        case .pulcherrima: "Forward"
        case .rasalgethi: "Informative"
        case .rasalhague: "Informative"
        case .sadachbia: "Lively"
        case .sadaltager: "Knowledgeable"
        case .sulafat: "Warm"
        case .umbriel: "Easy-going"
        case .vindemiatrix: "Gentle"
        }
    }
}

// MARK: - Session Mode

enum SessionMode {
    case text
    case audio
}

struct GeminiAudioSetupProfile: Equatable, Sendable {
    let startOfSpeechSensitivity: String
    let endOfSpeechSensitivity: String
    let prefixPaddingMs: Int
    let silenceDurationMs: Int
    let includesProactivity: Bool
    var activityHandling: String? = nil
    var turnCoverage: String? = nil
    var voiceName: String = GeminiVoice.aoede.rawValue

    static let echoRejectingDefault = GeminiAudioSetupProfile(
        startOfSpeechSensitivity: "START_SENSITIVITY_LOW",
        endOfSpeechSensitivity: "END_SENSITIVITY_LOW",
        prefixPaddingMs: 40,
        silenceDurationMs: 500,
        includesProactivity: false
    )

    static let noLowStartSensitivityWithProactivity = GeminiAudioSetupProfile(
        startOfSpeechSensitivity: "START_SENSITIVITY_HIGH",
        endOfSpeechSensitivity: "END_SENSITIVITY_LOW",
        prefixPaddingMs: 40,
        silenceDurationMs: 500,
        includesProactivity: true
    )

    static let fasterTurnTaking300ms = GeminiAudioSetupProfile(
        startOfSpeechSensitivity: "START_SENSITIVITY_LOW",
        endOfSpeechSensitivity: "END_SENSITIVITY_LOW",
        prefixPaddingMs: 40,
        silenceDurationMs: 300,
        includesProactivity: false
    )

    var automaticActivityDetection: [String: Any] {
        [
            "startOfSpeechSensitivity": startOfSpeechSensitivity,
            "endOfSpeechSensitivity": endOfSpeechSensitivity,
            "prefixPaddingMs": prefixPaddingMs,
            "silenceDurationMs": silenceDurationMs
        ]
    }

    var proactivityPayload: [String: Any]? {
        guard includesProactivity else { return nil }
        return ["proactiveAudio": true]
    }
}

struct SessionConfig {
    let mode: SessionMode
    let model: String
    let audioSetupProfile: GeminiAudioSetupProfile?

    // For Live API (voice/video calls) - requires audio input, outputs audio or text
    static let liveAudioModel = "gemini-2.5-flash-native-audio-preview-12-2025"
    
    // For standard text chat via generateContent REST API
    static let defaultTextModel = "gemini-2.5-flash"

    static func text(model: String = defaultTextModel) -> SessionConfig {
        SessionConfig(mode: .text, model: model, audioSetupProfile: nil)
    }

    static func audio(
        model: String = liveAudioModel,
        profile: GeminiAudioSetupProfile = .echoRejectingDefault
    ) -> SessionConfig {
        SessionConfig(mode: .audio, model: model, audioSetupProfile: profile)
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol GeminiServiceDelegate: AnyObject {
    func geminiServiceDidConnect(_ service: GeminiService)
    func geminiServiceDidDisconnect(_ service: GeminiService)
    func geminiService(_ service: GeminiService, didReceiveError error: Error)
    func geminiService(_ service: GeminiService, didReceiveTranscript transcript: String, isFinal: Bool)
    func geminiService(_ service: GeminiService, didReceiveInputTranscript transcript: String, isFinal: Bool)
    func geminiService(_ service: GeminiService, didReceiveResponse text: String)
    func geminiService(_ service: GeminiService, didReceiveAudio data: Data)
    func geminiService(_ service: GeminiService, didStartFunctionCall id: String, name: String, arguments: [String: Any])
    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: FunctionResult)
    func geminiServiceDidStartResponse(_ service: GeminiService)
    func geminiServiceDidEndResponse(_ service: GeminiService)
}

// MARK: - Gemini Service

@MainActor
class GeminiService: NSObject {
    private struct LiveAudioTrace {
        var connectedAt: Date?
        var firstOutboundAudioAt: Date?
        var firstInputTranscriptAt: Date?
        var firstModelEventAt: Date?
        var firstModelEventKind: String?
        var firstToolCallAt: Date?
        var firstInboundAudioAt: Date?
    }

    // MARK: - Properties

    weak var delegate: GeminiServiceDelegate?

    private let modelContext: ModelContext
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var isStreamingResponse = false
    private let supportsFileAttachments = false
    private var sentAudioChunkCount = 0
    private var sentAudioByteCount = 0
    private var receivedAudioChunkCount = 0
    private var receivedAudioByteCount = 0
    private var outboundTurnSequence = 0
    private var inboundTurnSequence = 0
    private var outboundTurnByMessageID: [UUID: String] = [:]
    private var inboundTurnID: String?
    private var inboundTurnStartedAt: Date?
    private var inboundTurnFirstEventLogged = false
    private var inboundTurnTextParts = 0
    private var inboundTurnAudioChunks = 0
    private var inboundTurnAudioBytes = 0
    private var inboundTurnTranscriptParts = 0
    private var inboundRESTTurnSequence = 0
    private var webSocketSessionSequence = 0
    private var activeWebSocketSessionID = "ws-0"
    private var pendingDisconnectReason = "none"
    private var ignoreSocketErrorsUntilNextConnect = false
    private var hasLoggedIgnoredSocketErrorForCurrentDisconnect = false
    private var liveAudioTrace = LiveAudioTrace()

    // Pending requests tracking with timeout
    private var pendingMessageID: UUID?
    private var timeoutTask: Task<Void, Never>?
    private var acceptanceTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    private let requestTimeout: TimeInterval = 30.0
    private let acceptanceTimeout: TimeInterval = 12.0
    
    var hasActiveSocketSession: Bool {
        webSocketTask != nil || urlSession != nil || activeConfig != nil || isConnected
    }
    private let streamHeartbeatTimeout: TimeInterval = 20.0

    private var hasAccepted = false
    private var lastStreamChunkAt: Date?
    private let promptConfigurationProvider: @MainActor () -> GeminiPromptConfiguration

    // API Configuration
    private let apiKey: String
    private(set) var activeConfig: SessionConfig?
    var currentMode: SessionMode? { activeConfig?.mode }
    private let baseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"
    private let restBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // Backend routing — when set, text chat and voice go through Cloud Run
    private let backendService = BackendService.shared
    private var chatSessionID: String = UUID().uuidString

    // REST conversation history (stateless API needs context each request)
    private var conversationHistory: [[String: Any]] = []
    private let maxConversationTurns = 20
    private var restTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        promptConfigurationProvider: @escaping @MainActor () -> GeminiPromptConfiguration = ChatSettings.currentPromptConfiguration
    ) {
        self.modelContext = modelContext
        self.promptConfigurationProvider = promptConfigurationProvider

        // Get API key from Info.plist (populated via Secrets.xcconfig) or environment
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        self.apiKey = plistKey ?? envKey ?? ""

        VoiceDiagnostics.gemini("[Gemini] API key loaded: \(!apiKey.isEmpty ? "✓" : "✗")")
        if apiKey.isEmpty {
            VoiceDiagnostics.fault("[Gemini] Info.plist key: \(!(plistKey?.isEmpty ?? true) ? "✓" : "✗")")
            VoiceDiagnostics.fault("[Gemini] Environment key: \(!(envKey?.isEmpty ?? true) ? "✓" : "✗")")
            VoiceDiagnostics.fault("[Gemini] Add GEMINI_API_KEY to Secrets.xcconfig or environment")
        }

        super.init()
    }

    // MARK: - Connection

    func connect(config: SessionConfig? = nil) {
        self.activeConfig = config ?? .text()
        webSocketSessionSequence += 1
        activeWebSocketSessionID = "ws-\(webSocketSessionSequence)"
        pendingDisconnectReason = "none"
        ignoreSocketErrorsUntilNextConnect = false
        hasLoggedIgnoredSocketErrorForCurrentDisconnect = false
        logSocketEvent(
            "connect requested",
            extra: "mode=\(describe(mode: activeConfig?.mode)) model=\(activeConfig?.model ?? "none") existingTask=\(webSocketTask != nil)"
        )

        // Route through Cloud Run backend for voice relay
        let voiceName = (config?.audioSetupProfile ?? .echoRejectingDefault).voiceName
        let backendVoiceURL = backendService.voiceURL + "?user_id=default&voice=\(voiceName)"
        let urlString = backendVoiceURL
        guard let url = URL(string: urlString) else {
            delegate?.geminiService(self, didReceiveError: GeminiError.invalidURL)
            return
        }

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessage()

        acceptanceTask?.cancel()
        acceptanceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.acceptanceTimeout * 1_000_000_000))
                if !self.hasAccepted && !self.isConnected {
                    self.logSocketEvent("acceptance timeout")
                    await MainActor.run {
                        self.delegate?.geminiService(self, didReceiveError: GeminiError.connectionFailed)
                        self.pendingDisconnectReason = "acceptance-timeout"
                        self.ignoreSocketErrorsUntilNextConnect = true
                        self.hasLoggedIgnoredSocketErrorForCurrentDisconnect = false
                        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                        self.resetTrackingState()
                    }
                }
            } catch {
                // Task cancelled, no action needed
            }
        }
    }

    func disconnect(reason: String = "manual") {
        pendingDisconnectReason = reason
        ignoreSocketErrorsUntilNextConnect = true
        hasLoggedIgnoredSocketErrorForCurrentDisconnect = false
        logSocketEvent("disconnect requested", extra: "reason=\(reason)")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        isStreamingResponse = false
        activeConfig = nil

        acceptanceTask?.cancel()
        acceptanceTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        restTask?.cancel()
        restTask = nil

        resetTrackingState()
    }

    // MARK: - Mode Switching

    /// Switch to audio mode (for live voice calls)
    func switchToAudioMode() {
        disconnect(reason: "switchToAudioMode")
        connect(config: .audio())
    }

    private func resetTrackingState() {
        hasAccepted = false
        lastStreamChunkAt = nil
        pendingMessageID = nil
        liveAudioTrace = LiveAudioTrace()
    }

    private func describe(mode: SessionMode?) -> String {
        switch mode {
        case .audio:
            return "audio"
        case .text:
            return "text"
        case .none:
            return "none"
        }
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        VoiceDiagnostics.gemini(message())
    }

    private func faultLog(_ message: @autoclosure () -> String) {
        VoiceDiagnostics.fault(message())
    }

    private func logSocketEvent(_ event: String, extra: String = "") {
        let linkedPendingMessage = pendingMessageID.map { String($0.uuidString.prefix(8)) } ?? "none"
        let lastChunkAgeMs = lastStreamChunkAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        let inboundTurn = inboundTurnID ?? "none"
        let suffix = extra.isEmpty ? "" : " \(extra)"
        debugLog(
            "[Gemini] \(activeWebSocketSessionID) \(event)\(suffix) | connected=\(isConnected) accepted=\(hasAccepted) streaming=\(isStreamingResponse) mode=\(describe(mode: currentMode)) pendingMessage=\(linkedPendingMessage) inboundTurn=\(inboundTurn) lastChunkAgeMs=\(lastChunkAgeMs) disconnectReason=\(pendingDisconnectReason)"
        )
    }

    // MARK: - Setup Message

    private func sendSetupMessage() {
        // Backend handles the Gemini setup message (system prompt, tools, voice config).
        // The setup complete response is relayed from backend → client.
        let config = activeConfig ?? .audio()
        logSocketEvent("setup delegated to backend", extra: "mode=\(describe(mode: config.mode))")
    }

    func makeSetupPayload(config: SessionConfig) -> [String: Any] {
        var setup: [String: Any] = [
            "model": "models/\(config.model)",
            "systemInstruction": [
                "parts": [
                    ["text": makeSystemPrompt(for: config.mode)]
                ]
            ],
            "tools": [
                ["functionDeclarations": GeminiTools.toAPIFormat()]
            ]
        ]

        switch config.mode {
        case .audio:
            let profile = config.audioSetupProfile ?? .echoRejectingDefault
            setup["generationConfig"] = [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": [
                            "voiceName": profile.voiceName
                        ]
                    ]
                ]
            ]
            var realtimeInputConfig: [String: Any] = [
                "automaticActivityDetection": profile.automaticActivityDetection
            ]
            if let activityHandling = profile.activityHandling {
                realtimeInputConfig["activityHandling"] = activityHandling
            }
            if let turnCoverage = profile.turnCoverage {
                realtimeInputConfig["turnCoverage"] = turnCoverage
            }
            setup["realtimeInputConfig"] = realtimeInputConfig
            if let proactivity = profile.proactivityPayload {
                setup["proactivity"] = proactivity
            }
            setup["outputAudioTranscription"] = [String: Any]()
            setup["inputAudioTranscription"] = [String: Any]()
        case .text:
            setup["generationConfig"] = [
                "responseModalities": ["TEXT"]
            ]
        }

        return ["setup": setup]
    }

    func makeSystemPrompt(for mode: SessionMode) -> String {
        promptConfigurationProvider().prompt(for: mode)
    }

    // MARK: - Pending Request Tracking

    @MainActor
    private func startRequestTracking(messageID: UUID) {
        timeoutTask?.cancel()
        pendingMessageID = messageID

        timeoutTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: UInt64(self.requestTimeout * 1_000_000_000))
                self.handleRequestTimeout(messageID: messageID)
            } catch {
            }
        }
    }

    private func handleRequestTimeout(messageID: UUID) {
        Task { @MainActor [weak self] in
            guard self?.pendingMessageID == messageID else { return }
            self?.pendingMessageID = nil
            self?.timeoutTask = nil
            self?.delegate?.geminiService(self!, didReceiveError: GeminiError.requestTimeout)
        }
    }

    @MainActor
    private func cancelRequestTracking(messageID: UUID) {
        guard pendingMessageID == messageID else { return }
        pendingMessageID = nil
        outboundTurnByMessageID.removeValue(forKey: messageID)
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    func notifySendResult(messageID: UUID) {
        cancelRequestTracking(messageID: messageID)
    }

    func notifyCurrentSendResult() {
        guard let pendingMessageID else { return }
        cancelRequestTracking(messageID: pendingMessageID)
    }

    // MARK: - Audio Streaming

    func sendAudio(data: Data) {
        guard isConnected else {
            debugLog("[Gemini] Dropping audio chunk while disconnected, bytes=\(data.count)")
            return
        }

        if currentMode == .audio, liveAudioTrace.firstOutboundAudioAt == nil {
            let now = Date()
            liveAudioTrace.firstOutboundAudioAt = now
            debugLog("[Gemini] \(activeWebSocketSessionID) liveTrace firstOutboundAudio bytes=\(data.count) msSinceConnect=\(millisecondsSinceLiveConnect(until: now))")
        }

        sentAudioChunkCount += 1
        sentAudioByteCount += data.count
        if sentAudioChunkCount == 1 || sentAudioChunkCount % 200 == 0 {
            debugLog("[Gemini] Sent audio chunk #\(sentAudioChunkCount), bytes=\(data.count), totalBytes=\(sentAudioByteCount)")
        }

        let base64Audio = data.base64EncodedString()

        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": base64Audio
                    ]
                ]
            ]
        ]

        sendJSON(message)
    }

    // MARK: - Text & Image Sending (Multimodal)

    /// Send a text message. Routes through REST API unless WebSocket is connected (during a call).
    func sendText(_ text: String, messageID: UUID? = nil) -> Result<Void, Error> {
        let turnID = nextOutboundTurnID(messageID: messageID)
        // During a call with active WebSocket, send via WebSocket
        if isConnected {
            debugLog("[Gemini] Outbound turn \(turnID) sendText(ws) chars=\(text.count) messageID=\(messageID?.uuidString ?? "none")")
            let message: [String: Any] = [
                "clientContent": [
                    "turns": [
                        [
                            "role": "user",
                            "parts": [
                                ["text": text]
                            ]
                        ]
                    ],
                    "turnComplete": true
                ]
            ]

            let result = sendJSON(message)
            if case .success = result, let id = messageID {
                startRequestTracking(messageID: id)
            }
            return result
        }

        // Otherwise use REST API
        debugLog("[Gemini] Outbound turn \(turnID) sendText(rest) chars=\(text.count) messageID=\(messageID?.uuidString ?? "none")")
        sendTextREST(text, messageID: messageID)
        return .success(())
    }

    /// Send an image. Routes through REST API unless WebSocket is connected (during a call).
    func sendPhoto(_ imageData: Data, messageID: UUID? = nil) -> Result<Void, Error> {
        let turnID = nextOutboundTurnID(messageID: messageID)
        if isConnected {
            debugLog("[Gemini] Outbound turn \(turnID) sendPhoto(ws) imageBytes=\(imageData.count) messageID=\(messageID?.uuidString ?? "none")")
            let base64Image = imageData.base64EncodedString()
            let message: [String: Any] = [
                "clientContent": [
                    "turns": [
                        [
                            "role": "user",
                            "parts": [
                                [
                                    "inlineData": [
                                        "mimeType": "image/jpeg",
                                        "data": base64Image
                                    ]
                                ]
                            ]
                        ]
                    ],
                    "turnComplete": true
                ]
            ]

            let result = sendJSON(message)
            if case .success = result, let id = messageID {
                startRequestTracking(messageID: id)
            }
            return result
        }

        debugLog("[Gemini] Outbound turn \(turnID) sendPhoto(rest) imageBytes=\(imageData.count) messageID=\(messageID?.uuidString ?? "none")")
        sendPhotoREST(imageData, messageID: messageID)
        return .success(())
    }

    /// Send text + image together. Routes through REST API unless WebSocket is connected.
    func sendTextWithPhoto(_ text: String, imageData: Data, messageID: UUID? = nil) -> Result<Void, Error> {
        let turnID = nextOutboundTurnID(messageID: messageID)
        if isConnected {
            debugLog("[Gemini] Outbound turn \(turnID) sendTextWithPhoto(ws) chars=\(text.count) imageBytes=\(imageData.count) messageID=\(messageID?.uuidString ?? "none")")
            let base64Image = imageData.base64EncodedString()
            let message: [String: Any] = [
                "clientContent": [
                    "turns": [
                        [
                            "role": "user",
                            "parts": [
                                ["text": text],
                                [
                                    "inlineData": [
                                        "mimeType": "image/jpeg",
                                        "data": base64Image
                                    ]
                                ]
                            ]
                        ]
                    ],
                    "turnComplete": true
                ]
            ]

            let result = sendJSON(message)
            if case .success = result, let id = messageID {
                startRequestTracking(messageID: id)
            }
            return result
        }

        debugLog("[Gemini] Outbound turn \(turnID) sendTextWithPhoto(rest) chars=\(text.count) imageBytes=\(imageData.count) messageID=\(messageID?.uuidString ?? "none")")
        sendTextWithPhotoREST(text, imageData: imageData, messageID: messageID)
        return .success(())
    }

    // MARK: - REST API Methods

    func sendTextREST(_ text: String, messageID: UUID? = nil) {
        let turnID = messageID.flatMap { outboundTurnByMessageID[$0] } ?? "out-unknown"
        debugLog("[Gemini] Outbound turn \(turnID) compose REST text parts=1 chars=\(text.count)")
        sendBackendRequest(text: text, messageID: messageID)
    }

    func sendPhotoREST(_ imageData: Data, messageID: UUID? = nil) {
        let turnID = messageID.flatMap { outboundTurnByMessageID[$0] } ?? "out-unknown"
        debugLog("[Gemini] Outbound turn \(turnID) compose REST image parts=1 imageBytes=\(imageData.count)")
        let base64Image = imageData.base64EncodedString()
        let userParts: [[String: Any]] = [
            ["inline_data": ["mime_type": "image/jpeg", "data": base64Image]]
        ]
        let userTurn: [String: Any] = ["role": "user", "parts": userParts]
        sendRESTRequest(userTurn: userTurn, messageID: messageID)
    }

    func sendTextWithPhotoREST(_ text: String, imageData: Data, messageID: UUID? = nil) {
        let turnID = messageID.flatMap { outboundTurnByMessageID[$0] } ?? "out-unknown"
        debugLog("[Gemini] Outbound turn \(turnID) compose REST text+image parts=2 chars=\(text.count) imageBytes=\(imageData.count)")
        let base64Image = imageData.base64EncodedString()
        let userParts: [[String: Any]] = [
            ["text": text],
            ["inline_data": ["mime_type": "image/jpeg", "data": base64Image]]
        ]
        let userTurn: [String: Any] = ["role": "user", "parts": userParts]
        sendRESTRequest(userTurn: userTurn, messageID: messageID)
    }

    // MARK: - Backend-Routed Text Chat

    /// Send text through the Cloud Run backend (ADK agent handles tool calling server-side).
    private func sendBackendRequest(text: String, messageID: UUID?) {
        let turnID = messageID.flatMap { outboundTurnByMessageID[$0] } ?? "out-unknown"
        let restInboundID = "in-rest-\(inboundRESTTurnSequence + 1)"
        let startedAt = Date()
        debugLog("[Gemini] Inbound turn \(restInboundID) started linkedOutbound=\(turnID) mode=backend")
        delegate?.geminiServiceDidStartResponse(self)

        restTask?.cancel()
        restTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sessionID = await MainActor.run { self.chatSessionID }
                let responseText = try await self.backendService.sendText(text, sessionID: sessionID)
                await MainActor.run {
                    if !responseText.isEmpty {
                        let preview = responseText.count > 160 ? String(responseText.prefix(160)) + "..." : responseText
                        self.debugLog("[Gemini] Inbound turn \(restInboundID) backendText chars=\(responseText.count) preview=\(preview)")
                        self.delegate?.geminiService(self, didReceiveResponse: responseText)
                    }
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.debugLog("[Gemini] Inbound turn \(restInboundID) complete elapsedMs=\(elapsedMs)")
                    self.inboundRESTTurnSequence += 1
                    self.delegate?.geminiServiceDidEndResponse(self)
                }
            } catch is CancellationError {
                // Task cancelled
            } catch {
                await MainActor.run {
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.debugLog("[Gemini] Inbound turn \(restInboundID) failed elapsedMs=\(elapsedMs) error=\(error.localizedDescription)")
                    self.inboundRESTTurnSequence += 1
                    self.delegate?.geminiService(self, didReceiveError: error)
                    self.delegate?.geminiServiceDidEndResponse(self)
                }
            }
        }
    }

    // MARK: - Legacy Direct REST (used for photo endpoints until Phase 5)

    private func sendRESTRequest(userTurn: [String: Any], messageID: UUID?) {
        let turnID = messageID.flatMap { outboundTurnByMessageID[$0] } ?? "out-unknown"
        let restInboundID = "in-rest-\(inboundRESTTurnSequence + 1)"
        let startedAt = Date()
        debugLog("[Gemini] Inbound turn \(restInboundID) started linkedOutbound=\(turnID) mode=rest(legacy-direct)")
        delegate?.geminiServiceDidStartResponse(self)

        // Append user turn to history (still used for direct REST fallback on photos)
        conversationHistory.append(userTurn)
        trimConversationHistory()

        restTask?.cancel()
        restTask = Task { [weak self] in
            guard let self else { return }
            do {
                let responseText = try await self.executeRESTRequest(messageID: messageID)
                await MainActor.run {
                    if !responseText.isEmpty {
                        let preview = responseText.count > 160 ? String(responseText.prefix(160)) + "..." : responseText
                        self.debugLog("[Gemini] Inbound turn \(restInboundID) restText chars=\(responseText.count) preview=\(preview)")
                        self.delegate?.geminiService(self, didReceiveResponse: responseText)
                    }
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.debugLog("[Gemini] Inbound turn \(restInboundID) complete elapsedMs=\(elapsedMs)")
                    self.inboundRESTTurnSequence += 1
                    self.delegate?.geminiServiceDidEndResponse(self)
                }
            } catch is CancellationError {
                // Task cancelled, no action
            } catch {
                await MainActor.run {
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.debugLog("[Gemini] Inbound turn \(restInboundID) failed elapsedMs=\(elapsedMs) error=\(error.localizedDescription)")
                    self.inboundRESTTurnSequence += 1
                    self.delegate?.geminiService(self, didReceiveError: error)
                    self.delegate?.geminiServiceDidEndResponse(self)
                }
            }
        }
    }

    private func executeRESTRequest(messageID: UUID?) async throws -> String {
        let model = SessionConfig.defaultTextModel
        let urlString = "\(restBaseURL)/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        let body = buildRESTBody()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.connectionFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            faultLog("[Gemini REST] HTTP \(httpResponse.statusCode): \(errorBody)")
            if httpResponse.statusCode == 429 {
                throw GeminiError.requestTimeout
            }
            throw GeminiError.serviceUnavailable
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.invalidJSON
        }

        // Function calling loop removed — tool execution is handled server-side.
        // This direct REST path is only used for photo endpoints (Phase 5 will
        // route those through the backend too).

        // Extract text response
        let textParts = parts.compactMap { $0["text"] as? String }
        let responseText = textParts.joined()

        // Append assistant turn to history
        if !responseText.isEmpty {
            let modelTurn: [String: Any] = ["role": "model", "parts": [["text": responseText]]]
            conversationHistory.append(modelTurn)
            trimConversationHistory()
        }

        return responseText
    }

    private func buildRESTBody() -> [String: Any] {
        [
            "contents": conversationHistory,
            "systemInstruction": [
                "parts": [["text": makeSystemPrompt(for: .text)]]
            ],
            "tools": [
                ["functionDeclarations": GeminiTools.toAPIFormat()]
            ]
        ]
    }

    private func millisecondsSinceLiveConnect(until date: Date) -> Int {
        guard let connectedAt = liveAudioTrace.connectedAt else { return -1 }
        return Int(date.timeIntervalSince(connectedAt) * 1000)
    }

    private func millisecondsSinceFirstOutboundAudio(until date: Date) -> Int {
        guard let firstOutboundAudioAt = liveAudioTrace.firstOutboundAudioAt else { return -1 }
        return Int(date.timeIntervalSince(firstOutboundAudioAt) * 1000)
    }

    private func recordFirstInputTranscriptIfNeeded(chars: Int) {
        guard currentMode == .audio, liveAudioTrace.firstInputTranscriptAt == nil else { return }
        let now = Date()
        liveAudioTrace.firstInputTranscriptAt = now
        debugLog(
            "[Gemini] \(activeWebSocketSessionID) liveTrace firstInputTranscript chars=\(chars) msSinceConnect=\(millisecondsSinceLiveConnect(until: now)) msSinceFirstOutboundAudio=\(millisecondsSinceFirstOutboundAudio(until: now))"
        )
    }

    private func recordFirstModelEventIfNeeded(kind: String, extra: String) {
        guard currentMode == .audio, liveAudioTrace.firstModelEventAt == nil else { return }
        let now = Date()
        liveAudioTrace.firstModelEventAt = now
        liveAudioTrace.firstModelEventKind = kind
        debugLog(
            "[Gemini] \(activeWebSocketSessionID) liveTrace firstModelEvent kind=\(kind) \(extra) msSinceConnect=\(millisecondsSinceLiveConnect(until: now)) msSinceFirstOutboundAudio=\(millisecondsSinceFirstOutboundAudio(until: now))"
        )
    }

    private func recordFirstToolCallIfNeeded(count: Int) {
        guard currentMode == .audio, liveAudioTrace.firstToolCallAt == nil else { return }
        let now = Date()
        liveAudioTrace.firstToolCallAt = now
        debugLog(
            "[Gemini] \(activeWebSocketSessionID) liveTrace firstToolCall count=\(count) msSinceConnect=\(millisecondsSinceLiveConnect(until: now)) msSinceFirstOutboundAudio=\(millisecondsSinceFirstOutboundAudio(until: now))"
        )
    }

    private func recordFirstInboundAudioIfNeeded(bytes: Int) {
        guard currentMode == .audio, liveAudioTrace.firstInboundAudioAt == nil else { return }
        let now = Date()
        liveAudioTrace.firstInboundAudioAt = now
        debugLog(
            "[Gemini] \(activeWebSocketSessionID) liveTrace firstInboundAudio bytes=\(bytes) msSinceConnect=\(millisecondsSinceLiveConnect(until: now)) msSinceFirstOutboundAudio=\(millisecondsSinceFirstOutboundAudio(until: now))"
        )
    }

    private func trimConversationHistory() {
        // Each turn is one entry; cap at maxConversationTurns
        while conversationHistory.count > maxConversationTurns {
            conversationHistory.removeFirst()
        }
    }

    func clearConversationHistory() {
        conversationHistory.removeAll()
    }

    // MARK: - Video Streaming

    /// Send a JPEG video frame over the Live API realtime input.
    /// Uses image/jpeg per Google Live API examples.
    func sendVideoFrame(_ imageData: Data) {
        guard isConnected else { return }
        debugLog("[Gemini] Outbound realtime video frame send bytes=\(imageData.count)")

        let base64Image = imageData.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "image/jpeg",
                        "data": base64Image
                    ]
                ]
            ]
        ]

        sendJSON(message)
    }

    // MARK: - File Attachments (Stub)

    func sendVideoAttachment(url: URL, utType: String?) {
        guard isConnected else {
            debugLog("[Gemini] Video attachment skipped (not connected). url=\(url.lastPathComponent)")
            return
        }
        guard supportsFileAttachments else {
            debugLog("[Gemini] Video attachment reached stub boundary. file=\(url.lastPathComponent) utType=\(utType ?? "unknown") reason=file-attachment-upload-not-implemented")
            return
        }
        // TODO: Upload video attachment when Gemini supports it.
        _ = (url, utType)
    }

    func sendDocumentAttachment(url: URL, utType: String?) {
        guard isConnected else {
            debugLog("[Gemini] Document attachment skipped (not connected). url=\(url.lastPathComponent)")
            return
        }
        guard supportsFileAttachments else {
            debugLog("[Gemini] Document attachment reached stub boundary. file=\(url.lastPathComponent) utType=\(utType ?? "unknown") reason=file-attachment-upload-not-implemented")
            return
        }
        // TODO: Upload document attachment when Gemini supports it.
        _ = (url, utType)
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { result in
            Task { @MainActor in
                self.handleReceiveResult(result)
            }
        }
    }

    func handleReceiveResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            handleMessage(message)
            receiveMessage()

        case .failure(let error):
            if shouldIgnoreSocketError(error) {
                logIgnoredSocketErrorIfNeeded(prefix: "receive", error: error)
                return
            }

            logSocketEvent("receive error", extra: "error=\(error.localizedDescription)")
            delegate?.geminiService(self, didReceiveError: error)
            acceptanceTask?.cancel()
            acceptanceTask = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
            resetTrackingState()
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleTextMessage(text)
            } else {
                debugLog("[Gemini] Received non-UTF8 binary frame (\(data.count) bytes)")
            }
        @unknown default:
            break
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let trimmed = text.count > 300 ? String(text.prefix(300)) + "..." : text
            debugLog("[Gemini] Received non-JSON text frame: \(trimmed)")
            return
        }

        if !hasAccepted {
            logSocketEvent("pre-accept message", extra: "payload=\(json)")
        }

        if let serverError = parseServerError(json) {
            logSocketEvent("server error", extra: "message=\(serverError)")
            delegate?.geminiService(self, didReceiveError: GeminiError.serverError(serverError))
            return
        }

        // Handle setup complete
        if json["setupComplete"] != nil || json["setup_complete"] != nil {
            hasAccepted = true
            acceptanceTask?.cancel()
            acceptanceTask = nil
            isConnected = true
            liveAudioTrace.connectedAt = Date()
            sentAudioChunkCount = 0
            sentAudioByteCount = 0
            receivedAudioChunkCount = 0
            receivedAudioByteCount = 0
            logSocketEvent("setup complete acknowledged")
            delegate?.geminiServiceDidConnect(self)
            return
        }

        // Handle server content
        if let serverContent = (json["serverContent"] as? [String: Any]) ?? (json["server_content"] as? [String: Any]) {
            handleServerContent(serverContent)
            return
        }

        // Handle tool call
        if let toolCall = (json["toolCall"] as? [String: Any]) ?? (json["tool_call"] as? [String: Any]) {
            handleToolCall(toolCall)
            return
        }

        if let goAway = json["goAway"] as? [String: Any] {
            let timeLeft = goAway["timeLeft"] as? String ?? "unknown"
            logSocketEvent("server goAway received", extra: "timeLeft=\(timeLeft)")
            return
        }

    }

    private func handleServerContent(_ content: [String: Any]) {
        // Accept on first content
        if !hasAccepted {
            hasAccepted = true
            acceptanceTask?.cancel()
            acceptanceTask = nil
            debugLog("[Gemini] Accepted and responding")
        }

        // Handle input transcript (user speech-to-text in audio mode)
        let turnComplete = (content["turnComplete"] as? Bool) ?? (content["turn_complete"] as? Bool) ?? false

        if let inputTranscript = (content["inputTranscript"] as? String) ?? (content["input_transcript"] as? String) {
            recordFirstInputTranscriptIfNeeded(chars: inputTranscript.count)
            delegate?.geminiService(self, didReceiveInputTranscript: inputTranscript, isFinal: turnComplete)
        }
        if let inputTranscription = content["inputTranscription"] as? [String: Any],
           let transcript = inputTranscription["text"] as? String {
            recordFirstInputTranscriptIfNeeded(chars: transcript.count)
            delegate?.geminiService(self, didReceiveInputTranscript: transcript, isFinal: turnComplete)
        }
        if let inputTranscription = content["input_audio_transcription"] as? [String: Any],
           let transcript = inputTranscription["text"] as? String {
            recordFirstInputTranscriptIfNeeded(chars: transcript.count)
            delegate?.geminiService(self, didReceiveInputTranscript: transcript, isFinal: turnComplete)
        }

        // Handle model turn (text, audio, output transcript)
        if let modelTurn = (content["modelTurn"] as? [String: Any]) ?? (content["model_turn"] as? [String: Any]),
           let parts = modelTurn["parts"] as? [[String: Any]] {

            lastStreamChunkAt = Date()

            if !isStreamingResponse {
                isStreamingResponse = true
                inboundTurnSequence += 1
                let turnID = "in-\(inboundTurnSequence)"
                inboundTurnID = turnID
                inboundTurnStartedAt = Date()
                inboundTurnFirstEventLogged = false
                inboundTurnTextParts = 0
                inboundTurnAudioChunks = 0
                inboundTurnAudioBytes = 0
                inboundTurnTranscriptParts = 0
                let linkedOutbound: String = {
                    guard let pending = pendingMessageID else { return "none" }
                    return outboundTurnByMessageID[pending] ?? "msg-\(pending.uuidString.prefix(8))"
                }()
                debugLog("[Gemini] Inbound turn \(turnID) started linkedOutbound=\(linkedOutbound)")
                delegate?.geminiServiceDidStartResponse(self)

                // Start heartbeat monitor
                heartbeatTask?.cancel()
                heartbeatTask = Task { [weak self] in
                    guard let self else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: UInt64(self.streamHeartbeatTimeout * 1_000_000_000))
                        await MainActor.run {
                            if self.isStreamingResponse,
                               let last = self.lastStreamChunkAt,
                               Date().timeIntervalSince(last) > self.streamHeartbeatTimeout {
                                self.debugLog("[Gemini] Stream heartbeat timeout")
                                self.delegate?.geminiService(self, didReceiveError: GeminiError.requestTimeout)
                                self.isStreamingResponse = false
                                self.delegate?.geminiServiceDidEndResponse(self)
                                self.heartbeatTask?.cancel()
                                self.heartbeatTask = nil
                            }
                        }
                    }
                }
            }

            for part in parts {
                // Text response
                if let text = part["text"] as? String {
                    inboundTurnTextParts += 1
                    recordFirstModelEventIfNeeded(kind: "text", extra: "chars=\(text.count)")
                    if !inboundTurnFirstEventLogged, let turnID = inboundTurnID {
                        inboundTurnFirstEventLogged = true
                        debugLog("[Gemini] Inbound turn \(turnID) firstEvent=text chars=\(text.count)")
                    }
                    delegate?.geminiService(self, didReceiveResponse: text)
                }

                // Audio response
                if let inlineData = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any]),
                   let base64Data = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: base64Data) {
                    receivedAudioChunkCount += 1
                    receivedAudioByteCount += audioData.count
                    inboundTurnAudioChunks += 1
                    inboundTurnAudioBytes += audioData.count
                    recordFirstModelEventIfNeeded(kind: "audio", extra: "bytes=\(audioData.count)")
                    recordFirstInboundAudioIfNeeded(bytes: audioData.count)
                    if !inboundTurnFirstEventLogged, let turnID = inboundTurnID {
                        inboundTurnFirstEventLogged = true
                        debugLog("[Gemini] Inbound turn \(turnID) firstEvent=audio bytes=\(audioData.count)")
                    }
                    if receivedAudioChunkCount == 1 || receivedAudioChunkCount % 200 == 0 {
                        debugLog("[Gemini] Received audio chunk #\(receivedAudioChunkCount), bytes=\(audioData.count), totalBytes=\(receivedAudioByteCount)")
                    }
                    delegate?.geminiService(self, didReceiveAudio: audioData)
                }

                // Output transcript (AI speech-to-text)
                if let transcript = part["transcript"] as? String {
                    inboundTurnTranscriptParts += 1
                    recordFirstModelEventIfNeeded(kind: "transcript", extra: "chars=\(transcript.count)")
                    if !inboundTurnFirstEventLogged, let turnID = inboundTurnID {
                        inboundTurnFirstEventLogged = true
                        debugLog("[Gemini] Inbound turn \(turnID) firstEvent=transcript chars=\(transcript.count)")
                    }
                    delegate?.geminiService(self, didReceiveTranscript: transcript, isFinal: turnComplete)
                }
            }

            if let id = pendingMessageID {
                cancelRequestTracking(messageID: id)
            }
        }

        let isComplete = turnComplete
        if isComplete {
            if let turnID = inboundTurnID {
                let elapsedMs = Int((Date().timeIntervalSince(inboundTurnStartedAt ?? Date())) * 1000)
                debugLog("[Gemini] Inbound turn \(turnID) complete elapsedMs=\(elapsedMs) textParts=\(inboundTurnTextParts) audioChunks=\(inboundTurnAudioChunks) audioBytes=\(inboundTurnAudioBytes) transcriptParts=\(inboundTurnTranscriptParts)")
            }
            isStreamingResponse = false
            heartbeatTask?.cancel()
            heartbeatTask = nil
            lastStreamChunkAt = nil
            inboundTurnID = nil
            inboundTurnStartedAt = nil
            inboundTurnFirstEventLogged = false
            inboundTurnTextParts = 0
            inboundTurnAudioChunks = 0
            inboundTurnAudioBytes = 0
            inboundTurnTranscriptParts = 0
            delegate?.geminiServiceDidEndResponse(self)
        }

        if let outputTranscription = content["outputTranscription"] as? [String: Any],
           let transcript = outputTranscription["text"] as? String {
            delegate?.geminiService(self, didReceiveTranscript: transcript, isFinal: turnComplete)
        }
        if let outputTranscription = content["output_audio_transcription"] as? [String: Any],
           let transcript = outputTranscription["text"] as? String {
            delegate?.geminiService(self, didReceiveTranscript: transcript, isFinal: turnComplete)
        }
    }

    // MARK: - Function Calling

    private func handleToolCall(_ toolCall: [String: Any]) {
        // Tool calls are now handled server-side by the ADK agent (text) or
        // the voice relay endpoint (voice). If we receive one here, log it
        // but don't execute — the backend is responsible.
        let functionCalls = toolCall["functionCalls"] as? [[String: Any]] ?? []
        recordFirstToolCallIfNeeded(count: functionCalls.count)
        debugLog("[Gemini] Tool call received but handled server-side count=\(functionCalls.count)")

        // Still notify delegate for UI chip display
        for rawCall in functionCalls {
            guard let id = rawCall["id"] as? String,
                  let name = rawCall["name"] as? String,
                  let args = rawCall["args"] as? [String: Any] else {
                continue
            }
            delegate?.geminiService(self, didStartFunctionCall: id, name: name, arguments: args)
        }
    }

    // Tool execution has moved to the Cloud Run backend (ADK agent + Firestore).
    // The 14 inventory/recipe tool functions previously here are now in
    // backend/cooking_agent/tools.py and execute server-side.


    @discardableResult
    private func sendJSON(_ json: [String: Any]) -> Result<Void, Error> {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8) else {
            faultLog("[Gemini] Invalid JSON payload: \(json)")
            return .failure(GeminiError.invalidJSON)
        }

        guard let task = webSocketTask else {
            return .failure(GeminiError.connectionFailed)
        }

        task.send(.string(string)) { [weak self] error in
            if let error = error {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.shouldIgnoreSocketError(error) {
                        self.logIgnoredSocketErrorIfNeeded(prefix: "send", error: error)
                        return
                    }
                    self.logSocketEvent("send error", extra: "error=\(error.localizedDescription)")
                    self.delegate?.geminiService(self, didReceiveError: error)
                }
            }
        }

        return .success(())
    }

    private func parseServerError(_ json: [String: Any]) -> String? {
        guard let error = json["error"] as? [String: Any] else { return nil }
        let message = error["message"] as? String ?? "Unknown server error"
        if let code = error["code"] as? Int {
            return "\(message) (code \(code))"
        }
        return message
    }

    private func nextOutboundTurnID(messageID: UUID?) -> String {
        outboundTurnSequence += 1
        let turnID = "out-\(outboundTurnSequence)"
        if let messageID {
            outboundTurnByMessageID[messageID] = turnID
        }
        return turnID
    }

    private func shouldIgnoreSocketError(_ error: any Error) -> Bool {
        _ = error
        guard ignoreSocketErrorsUntilNextConnect else { return false }
        return true
    }

    private func logIgnoredSocketErrorIfNeeded(prefix: String, error: any Error) {
        guard !hasLoggedIgnoredSocketErrorForCurrentDisconnect else { return }
        hasLoggedIgnoredSocketErrorForCurrentDisconnect = true
        debugLog("[Gemini] Ignoring \(prefix) error during expected disconnect: \(error.localizedDescription)")
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.logSocketEvent("websocket opened", extra: "protocol=\(`protocol` ?? "none")")
            self.sendSetupMessage()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        Task { @MainActor in
            self.logSocketEvent(
                "websocket closed",
                extra: "code=\(closeCode.rawValue) reason=\(reasonStr) initiatedBy=\(self.pendingDisconnectReason)"
            )
            self.isConnected = false
            self.isStreamingResponse = false

            self.acceptanceTask?.cancel()
            self.acceptanceTask = nil
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.heartbeatTask?.cancel()
            self.heartbeatTask = nil

            self.resetTrackingState()
            self.pendingDisconnectReason = "none"

            self.delegate?.geminiServiceDidDisconnect(self)
        }
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case connectionFailed
    case requestTimeout
    case serviceUnavailable
    case cancelled
    case invalidJSON
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not configured. Add GEMINI_API_KEY to Info.plist or environment."
        case .invalidURL:
            return "Invalid API URL"
        case .connectionFailed:
            return "Failed to connect to Gemini"
        case .requestTimeout:
            return "Request timed out - Gemini may be busy or rate limited"
        case .serviceUnavailable:
            return "Service temporarily unavailable"
        case .cancelled:
            return "Request was cancelled"
        case .invalidJSON:
            return "Failed to encode message"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
