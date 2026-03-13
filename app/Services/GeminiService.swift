import Foundation
import SwiftData
import VoiceCore

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

    // API Configuration
    private let apiKey: String
    private(set) var activeConfig: SessionConfig?
    var currentMode: SessionMode? { activeConfig?.mode }
    private let baseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"
    private let restBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // REST conversation history (stateless API needs context each request)
    private var conversationHistory: [[String: Any]] = []
    private let maxConversationTurns = 20
    private var restTask: Task<Void, Never>?

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

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
        guard !apiKey.isEmpty else {
            delegate?.geminiService(self, didReceiveError: GeminiError.missingAPIKey)
            return
        }

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

        let urlString = "\(baseURL)?key=\(apiKey)"
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
        let config = activeConfig ?? .audio()
        let model = config.model
        let payload = makeSetupPayload(config: config)
        logSocketEvent("sending setup", extra: "model=\(model) mode=\(describe(mode: config.mode))")
        if case let .failure(error) = sendJSON(payload) {
            faultLog("[Gemini] Setup send failed before dispatch: \(error.localizedDescription)")
            delegate?.geminiService(self, didReceiveError: error)
        }
    }

    func makeSetupPayload(config: SessionConfig) -> [String: Any] {
        var setup: [String: Any] = [
            "model": "models/\(config.model)",
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
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
                            "voiceName": "Aoede"
                        ]
                    ]
                ]
            ]
            setup["realtimeInputConfig"] = [
                "automaticActivityDetection": profile.automaticActivityDetection
            ]
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

    private var systemPrompt: String {
        """
        You are "Heard, Chef!" - a practical, knowledgeable sous chef who manages pantry + recipes efficiently.

        Core behavior:
        - Be concise, warm, and direct.
        - Acknowledge actions naturally with "Heard" or "Heard, chef" when appropriate.
        - Prefer taking reasonable action over blocking on minor missing details.
        - Ask clarifying questions only when a decision cannot be safely inferred.
        - Never refuse recipe creation just because some quantities/units are missing.
        - If a tool call fails, explain the issue simply and propose the fastest fix.
        - Avoid overhyped language and avoid "it's not X, it's Y" phrasing.

        Recipe guidance:
        - Quantities/units for salt, pepper, oils, butter, herbs, and spices are optional.
        - Accept vague quantity phrases ("some", "a handful", "to taste") without blocking.
        - Store freeform context (variations, pairing notes, tips) in recipe notes.

        \(Ingredient.schemaDescription)

        \(Recipe.schemaDescription)
        """
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
        let userParts: [[String: Any]] = [["text": text]]
        let userTurn: [String: Any] = ["role": "user", "parts": userParts]
        sendRESTRequest(userTurn: userTurn, messageID: messageID)
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

    private func sendRESTRequest(userTurn: [String: Any], messageID: UUID?) {
        guard !apiKey.isEmpty else {
            delegate?.geminiService(self, didReceiveError: GeminiError.missingAPIKey)
            return
        }

        let turnID = messageID.flatMap { outboundTurnByMessageID[$0] } ?? "out-unknown"
        let restInboundID = "in-rest-\(inboundRESTTurnSequence + 1)"
        let startedAt = Date()
        debugLog("[Gemini] Inbound turn \(restInboundID) started linkedOutbound=\(turnID) mode=rest")
        delegate?.geminiServiceDidStartResponse(self)

        // Append user turn to history
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
                    self.debugLog("[Gemini] Inbound turn \(restInboundID) complete elapsedMs=\(elapsedMs) textParts=\(responseText.isEmpty ? 0 : 1) audioChunks=0 audioBytes=0 transcriptParts=0")
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

        // Check for function calls
        let functionCalls = parts.compactMap { part -> (String, String, [String: Any])? in
            guard let fc = part["functionCall"] as? [String: Any],
                  let name = fc["name"] as? String else { return nil }
            let args = fc["args"] as? [String: Any] ?? [:]
            let id = UUID().uuidString
            return (id, name, args)
        }

        if !functionCalls.isEmpty {
            // Append model's function call turn to history
            let modelParts = parts
            let modelTurn: [String: Any] = ["role": "model", "parts": modelParts]
            conversationHistory.append(modelTurn)

            // Execute functions and collect results
            var functionResponses: [[String: Any]] = []
            for (id, name, args) in functionCalls {
                let call = FunctionCall(id: id, name: name, arguments: args)
                await MainActor.run {
                    self.delegate?.geminiService(self, didStartFunctionCall: id, name: name, arguments: args)
                }

                let result: FunctionResult
                if let validationError = GeminiTools.validate(call: call) {
                    result = .error(id: id, name: name, message: validationError)
                } else {
                    result = await MainActor.run { self.executeFunction(call) }
                }

                await MainActor.run {
                    self.delegate?.geminiService(self, didExecuteFunctionCall: name, result: result)
                }

                functionResponses.append([
                    "functionResponse": [
                        "name": name,
                        "response": result.response
                    ]
                ])
            }

            // Append tool response turn
            let toolTurn: [String: Any] = ["role": "user", "parts": functionResponses]
            conversationHistory.append(toolTurn)
            trimConversationHistory()

            // Follow-up request to get final text
            return try await executeRESTRequest(messageID: messageID)
        }

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
                "parts": [["text": systemPrompt]]
            ],
            "tools": [
                ["functionDeclarations": GeminiTools.toAPIFormat()]
            ]
        ]
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
            delegate?.geminiService(self, didReceiveInputTranscript: inputTranscript, isFinal: turnComplete)
        }
        if let inputTranscription = content["inputTranscription"] as? [String: Any],
           let transcript = inputTranscription["text"] as? String {
            delegate?.geminiService(self, didReceiveInputTranscript: transcript, isFinal: turnComplete)
        }
        if let inputTranscription = content["input_audio_transcription"] as? [String: Any],
           let transcript = inputTranscription["text"] as? String {
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
        guard let functionCalls = toolCall["functionCalls"] as? [[String: Any]] else { return }
        debugLog("[Gemini] Tool call batch received count=\(functionCalls.count)")

        for rawCall in functionCalls {
            guard let id = rawCall["id"] as? String,
                  let name = rawCall["name"] as? String,
                  let args = rawCall["args"] as? [String: Any] else {
                continue
            }

            let call = FunctionCall(id: id, name: name, arguments: args)
            delegate?.geminiService(self, didStartFunctionCall: id, name: name, arguments: args)

            // Validate the call
            if let validationError = GeminiTools.validate(call: call) {
                let result = FunctionResult.error(id: id, name: name, message: validationError)
                sendFunctionResponse(result)
                delegate?.geminiService(self, didExecuteFunctionCall: name, result: result)
                continue
            }

            // Execute the function
            let result = executeFunction(call)
            sendFunctionResponse(result)
            delegate?.geminiService(self, didExecuteFunctionCall: name, result: result)
        }
    }

    private func sendFunctionResponse(_ result: FunctionResult) {
        let response: [String: Any] = [
            "toolResponse": [
                "functionResponses": [result.toAPIFormat()]
            ]
        ]
        sendJSON(response)
    }

    private func executeFunction(_ call: FunctionCall) -> FunctionResult {
        switch call.name {
        // Inventory functions
        case "add_ingredient":
            return inventoryAdd(call)
        case "remove_ingredient":
            return inventoryRemove(call)
        case "update_ingredient":
            return inventoryUpdate(call)
        case "list_ingredients":
            return inventoryList(call)
        case "search_ingredients":
            return inventorySearch(call)
        case "get_ingredient":
            return inventoryCheck(call)
        // Recipe functions
        case "create_recipe":
            return recipeCreate(call)
        case "update_recipe":
            return recipeUpdate(call) // Added
        case "delete_recipe":
            return recipeDelete(call)
        case "get_recipe":
            return recipeGet(call)
        case "list_recipes":
            return recipeList(call)
        case "search_recipes":
            return recipeSearch(call)
        case "suggest_recipes":
            return recipeSuggest(call)
        case "check_recipe_availability":
            return recipeCheckAvailability(call)
        default:
            return .error(id: call.id, name: call.name, message: "Unknown function: \(call.name)")
        }
    }

    // MARK: - Inventory Functions

    private func inventoryAdd(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }
        guard let quantity = call.double("quantity"), quantity > 0 else {
            return .error(id: call.id, name: call.name, message: "Quantity must be greater than 0")
        }
        guard let unitStr = call.string("unit"),
              let unit = Unit.parse(unitStr) else {
            return .error(id: call.id, name: call.name, message: "Invalid unit. Valid units: \(Unit.allValidStrings.joined(separator: ", "))")
        }

        let category = call.string("category").flatMap { IngredientCategory.parse($0) } ?? .other
        let location = call.string("location").flatMap { StorageLocation.parse($0) } ?? .pantry
        let expiryDate = call.date("expiryDate")
        let notes = call.string("notes")

        let (ingredient, wasCreated) = Ingredient.findOrCreate(
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            location: location,
            expiryDate: expiryDate,
            notes: notes,
            mergeQuantity: true,
            in: modelContext
        )

        let message = wasCreated
            ? "Added \(ingredient.displayQuantity) of \(ingredient.name) to the \(ingredient.location.displayName)"
            : "Updated \(ingredient.name) - now have \(ingredient.displayQuantity) in the \(ingredient.location.displayName)"

        return .success(
            id: call.id,
            name: call.name,
            message: message,
            data: [
                "wasCreated": wasCreated,
                "ingredient": [
                    "name": ingredient.name,
                    "quantity": ingredient.quantity,
                    "unit": ingredient.unitRaw,
                    "location": ingredient.locationRaw
                ]
            ]
        )
    }

    private func inventoryRemove(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }

        guard let ingredient = Ingredient.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "'\(name)' not found in inventory")
        }

        if let quantity = call.double("quantity") {
            let removed = ingredient.removeQuantity(quantity)

            if ingredient.quantity <= 0 {
                modelContext.delete(ingredient)
                return .success(
                    id: call.id,
                    name: call.name,
                    message: "Removed all \(ingredient.name) from inventory"
                )
            }

            return .success(
                id: call.id,
                name: call.name,
                message: "Removed \(removed) \(ingredient.unitRaw) of \(ingredient.name). \(ingredient.displayQuantity) remaining.",
                data: ["remaining": ingredient.quantity]
            )
        }

        let ingredientName = ingredient.name
        modelContext.delete(ingredient)
        return .success(
            id: call.id,
            name: call.name,
            message: "Removed \(ingredientName) from inventory"
        )
    }

    private func inventoryUpdate(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }

        guard let patch = call.arguments["patch"] as? [String: Any] else {
            return .error(id: call.id, name: call.name, message: "Missing update patch")
        }

        guard let ingredient = Ingredient.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "'\(name)' not found in inventory")
        }

        var params = IngredientUpdateParams()
        if let newName = patch["name"] as? String { params.name = newName }
        if let quantity = parseDouble(patch["quantity"]) { params.quantity = quantity }
        if let unitStr = patch["unit"] as? String { params.unit = unitStr }
        if let categoryStr = patch["category"] as? String { params.category = categoryStr }
        if let locationStr = patch["location"] as? String { params.location = locationStr }
        if let expiryDate = parseDate(patch["expiryDate"]) { params.expiryDate = expiryDate }
        if let notes = patch["notes"] as? String { params.notes = notes }

        let hasChanges = params.name != nil
            || params.quantity != nil
            || params.unit != nil
            || params.category != nil
            || params.location != nil
            || params.expiryDate != nil
            || params.notes != nil

        if !hasChanges {
            return .error(id: call.id, name: call.name, message: "No changes specified")
        }

        ingredient.update(with: params)

        return .success(
            id: call.id,
            name: call.name,
            message: "Updated \(ingredient.name)",
            data: [
                "ingredient": [
                    "name": ingredient.name,
                    "quantity": ingredient.quantity,
                    "unit": ingredient.unitRaw,
                    "location": ingredient.locationRaw
                ]
            ]
        )
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: string) { return date }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.date(from: string)
    }

    private func inventoryList(_ call: FunctionCall) -> FunctionResult {
        let category = call.string("category").flatMap { IngredientCategory.parse($0) }
        let location = call.string("location").flatMap { StorageLocation.parse($0) }

        let ingredients = Ingredient.list(category: category, location: location, in: modelContext)

        if ingredients.isEmpty {
            var message = "No ingredients"
            if let cat = category { message += " in \(cat.displayName)" }
            if let loc = location { message += " in the \(loc.displayName)" }
            return .success(id: call.id, name: call.name, message: message, data: ["count": 0, "items": []])
        }

        let items = ingredients.map { "\($0.name): \($0.displayQuantity)" }
        var message = "\(ingredients.count) item\(ingredients.count == 1 ? "" : "s")"
        if let loc = location { message += " in the \(loc.displayName)" }
        if let cat = category { message += " (\(cat.displayName))" }

        return .success(
            id: call.id,
            name: call.name,
            message: message,
            data: ["count": ingredients.count, "items": items]
        )
    }

    private func inventorySearch(_ call: FunctionCall) -> FunctionResult {
        guard let query = call.string("query") else {
            return .error(id: call.id, name: call.name, message: "Missing search query")
        }

        let results = Ingredient.search(query: query, in: modelContext)
        if results.isEmpty {
            return .success(
                id: call.id,
                name: call.name,
                message: "No ingredients matching '\(query)'",
                data: ["count": 0, "results": []]
            )
        }

        let items = results.map { [
            "name": $0.name,
            "quantity": $0.displayQuantity,
            "location": $0.location.displayName
        ] }

        return .success(
            id: call.id,
            name: call.name,
            message: "Found \(results.count) matching ingredient\(results.count == 1 ? "" : "s")",
            data: ["count": results.count, "results": items]
        )
    }

    private func inventoryCheck(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }

        guard let ingredient = Ingredient.find(named: name, in: modelContext) else {
            return .success(
                id: call.id,
                name: call.name,
                message: "No '\(name)' in inventory",
                data: ["found": false]
            )
        }

        var data: [String: Any] = [
            "found": true,
            "name": ingredient.name,
            "quantity": ingredient.quantity,
            "unit": ingredient.unitRaw,
            "displayQuantity": ingredient.displayQuantity,
            "location": ingredient.location.displayName,
            "category": ingredient.category.displayName
        ]

        if let days = ingredient.daysUntilExpiry {
            data["daysUntilExpiry"] = days
            data["isExpired"] = ingredient.isExpired
            data["isExpiringSoon"] = ingredient.isExpiringSoon
        }

        let expiryInfo: String
        if ingredient.isExpired {
            expiryInfo = " (EXPIRED)"
        } else if ingredient.isExpiringSoon {
            expiryInfo = " (expiring soon)"
        } else {
            expiryInfo = ""
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "You have \(ingredient.displayQuantity) of \(ingredient.name) in the \(ingredient.location.displayName)\(expiryInfo)",
            data: data
        )
    }

    // MARK: - Recipe Functions

    private func recipeCreate(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        // Parse ingredients from JSON string
        guard let ingredientsJSON = call.string("ingredients"),
              let ingredientsData = ingredientsJSON.data(using: .utf8),
              let ingredientsArray = try? JSONSerialization.jsonObject(with: ingredientsData) as? [[String: Any]] else {
            return .error(id: call.id, name: call.name, message: "Invalid ingredients format - expected JSON array")
        }

        let recipeIngredients = ingredientsArray.compactMap { RecipeIngredient.fromArguments($0) }
        if recipeIngredients.isEmpty {
            return .error(id: call.id, name: call.name, message: "No valid ingredients provided")
        }

        // Parse steps from JSON string
        guard let stepsJSON = call.string("steps"),
              let stepsData = stepsJSON.data(using: .utf8),
              let stepsArray = try? JSONSerialization.jsonObject(with: stepsData) as? [Any] else {
            return .error(id: call.id, name: call.name, message: "Invalid steps format - expected JSON array")
        }

        var recipeSteps: [RecipeStep] = []
        for (index, stepItem) in stepsArray.enumerated() {
            if let stepStr = stepItem as? String {
                recipeSteps.append(RecipeStep(instruction: stepStr, orderIndex: index))
            } else if let stepDict = stepItem as? [String: Any],
                      let step = RecipeStep.fromArguments(stepDict, index: index) {
                recipeSteps.append(step)
            }
        }

        if recipeSteps.isEmpty {
            return .error(id: call.id, name: call.name, message: "No valid steps provided")
        }

        // Parse optional parameters
        let description = call.string("description")
        let notes = call.string("notes")
        let cookingTemperature = call.string("cookingTemperature")
        let prepTime = call.int("prepTime")
        let cookTime = call.int("cookTime")
        let servings = call.int("servings")
        let difficulty = call.string("difficulty").flatMap { RecipeDifficulty.parse($0) } ?? .medium

        var tags: [String] = []
        if let tagsJSON = call.string("tags"),
           let tagsData = tagsJSON.data(using: .utf8),
           let tagsArray = try? JSONSerialization.jsonObject(with: tagsData) as? [String] {
            tags = tagsArray
        }

        // Check if recipe already exists
        if Recipe.find(named: name, in: modelContext) != nil {
            return .error(id: call.id, name: call.name, message: "A recipe named '\(name)' already exists")
        }

        // Create the recipe
        let recipe = Recipe(
            name: name,
            description: description,
            notes: notes,
            cookingTemperature: cookingTemperature,
            ingredients: recipeIngredients,
            steps: recipeSteps,
            prepTime: prepTime,
            cookTime: cookTime,
            servings: servings,
            tags: tags,
            difficulty: difficulty,
            source: .aiDrafted
        )

        modelContext.insert(recipe)

        return .success(
            id: call.id,
            name: call.name,
            message: "Created recipe '\(recipe.name)' with \(recipeIngredients.count) ingredients and \(recipeSteps.count) steps",
            data: [
                "name": recipe.name,
                "ingredientCount": recipeIngredients.count,
                "stepCount": recipeSteps.count
            ]
        )
    }

    private func recipeUpdate(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        var changes: [String: Any] = [:]

        // Update simple fields
        if let newName = call.string("newName") { changes["name"] = newName }
        if let description = call.string("description") { changes["description"] = description }
        if call.arguments.keys.contains("notes") {
            changes["notes"] = call.string("notes") ?? ""
        }
        if call.arguments.keys.contains("cookingTemperature") {
            changes["cookingTemperature"] = call.string("cookingTemperature") ?? ""
        }
        if let prepTime = call.int("prepTime") { changes["prepTime"] = prepTime }
        if let cookTime = call.int("cookTime") { changes["cookTime"] = cookTime }
        if let servings = call.int("servings") { changes["servings"] = servings }
        if let difficulty = call.string("difficulty") { changes["difficulty"] = difficulty }

        // Update tags
        if let tagsJSON = call.string("tags"),
           let tagsData = tagsJSON.data(using: .utf8),
           let tagsArray = try? JSONSerialization.jsonObject(with: tagsData) as? [String] {
            changes["tags"] = tagsArray
        }

        // Update ingredients (Full Replace)
        if let ingredientsJSON = call.string("ingredients"),
           let ingredientsData = ingredientsJSON.data(using: .utf8),
           let ingredientsArray = try? JSONSerialization.jsonObject(with: ingredientsData) as? [[String: Any]] {
            let oldIngredients = recipe.ingredients
            let newIngredients = ingredientsArray.compactMap { RecipeIngredient.fromArguments($0) }
            recipe.ingredients = newIngredients // SwiftData relationship update
            for ingredient in oldIngredients {
                modelContext.delete(ingredient)
            }
            changes["ingredients"] = "\(newIngredients.count) items"
        }

        // Update steps (Full Replace)
        if let stepsJSON = call.string("steps"),
           let stepsData = stepsJSON.data(using: .utf8),
           let stepsArray = try? JSONSerialization.jsonObject(with: stepsData) as? [Any] {
            let oldSteps = recipe.steps
            var newSteps: [RecipeStep] = []
            for (index, stepItem) in stepsArray.enumerated() {
                if let stepStr = stepItem as? String {
                    newSteps.append(RecipeStep(instruction: stepStr, orderIndex: index))
                } else if let stepDict = stepItem as? [String: Any],
                          let step = RecipeStep.fromArguments(stepDict, index: index) {
                    newSteps.append(step)
                }
            }
            recipe.steps = newSteps // SwiftData relationship update
            for step in oldSteps {
                modelContext.delete(step)
            }
            changes["steps"] = "\(newSteps.count) steps"
        }

        recipe.update(from: changes)

        return .success(
            id: call.id,
            name: call.name,
            message: "Updated recipe '\(recipe.name)'",
            data: ["updatedFields": Array(changes.keys)]
        )
    }

    private func recipeList(_ call: FunctionCall) -> FunctionResult {
        let tag = call.string("tag")
        let recipes = Recipe.list(tag: tag, in: modelContext)

        if recipes.isEmpty {
            let message = if let tag { "No recipes with tag '\(tag)'" } else { "No recipes saved yet" }
            return .success(id: call.id, name: call.name, message: message, data: ["count": 0, "recipes": []])
        }

        let inventory = Ingredient.list(in: modelContext)
        let recipeList = recipes.map { recipe -> [String: Any] in
            let canMake = recipe.canMake(with: inventory)
            let missing = recipe.missingIngredients(from: inventory).count
            return [
                "name": recipe.name,
                "description": recipe.descriptionText ?? "",
                "cookingTemperature": recipe.cookingTemperature ?? "",
                "canMake": canMake,
                "missingCount": missing,
                "totalTime": recipe.formattedTotalTime ?? "Unknown",
                "difficulty": recipe.difficulty.displayName
            ]
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "\(recipes.count) recipe\(recipes.count == 1 ? "" : "s") found",
            data: ["count": recipes.count, "recipes": recipeList]
        )
    }

    private func recipeSearch(_ call: FunctionCall) -> FunctionResult {
        guard let query = call.string("query") else {
            return .error(id: call.id, name: call.name, message: "Missing search query")
        }

        let results = Recipe.search(query: query, in: modelContext)

        if results.isEmpty {
            return .success(
                id: call.id,
                name: call.name,
                message: "No recipes matching '\(query)'",
                data: ["count": 0, "results": []]
            )
        }

        let inventory = Ingredient.list(in: modelContext)
        let recipeList = results.map { recipe -> [String: Any] in
            [
                "name": recipe.name,
                "canMake": recipe.canMake(with: inventory),
                "missingCount": recipe.missingIngredients(from: inventory).count
            ]
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "Found \(results.count) recipe\(results.count == 1 ? "" : "s") matching '\(query)'",
            data: ["count": results.count, "results": recipeList]
        )
    }

    private func recipeSuggest(_ call: FunctionCall) -> FunctionResult {
        let inventory = Ingredient.list(in: modelContext)

        if inventory.isEmpty {
            return .success(
                id: call.id,
                name: call.name,
                message: "No ingredients in inventory. Add some ingredients first!",
                data: ["count": 0, "suggestions": []]
            )
        }

        let maxMissing = call.int("maxMissingIngredients") ?? 3
        let onlyFullyMakeable = call.bool("onlyFullyMakeable") ?? false

        var suggestions = Recipe.suggestFromInventory(
            inventory: inventory,
            maxMissingIngredients: maxMissing,
            in: modelContext
        )

        if onlyFullyMakeable {
            suggestions = suggestions.filter { $0.missing.isEmpty }
        }

        if suggestions.isEmpty {
            let message = onlyFullyMakeable
                ? "No recipes can be made with current inventory"
                : "No recipes found with \(maxMissing) or fewer missing ingredients"
            return .success(id: call.id, name: call.name, message: message, data: ["count": 0, "suggestions": []])
        }

        let suggestionList = suggestions.map { suggestion -> [String: Any] in
            [
                "name": suggestion.recipe.name,
                "matchPercentage": Int(suggestion.matchPercentage * 100),
                "missingIngredients": suggestion.missing.map { $0.name },
                "totalTime": suggestion.recipe.formattedTotalTime ?? "Unknown"
            ]
        }

        let fullyMakeableCount = suggestions.filter { $0.missing.isEmpty }.count

        return .success(
            id: call.id,
            name: call.name,
            message: "\(suggestions.count) recipe\(suggestions.count == 1 ? "" : "s") available. \(fullyMakeableCount) can be made right now.",
            data: ["count": suggestions.count, "fullyMakeable": fullyMakeableCount, "suggestions": suggestionList]
        )
    }

    private func recipeGet(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        let inventory = Ingredient.list(in: modelContext)
        let missing = recipe.missingIngredients(from: inventory)

        let ingredientList = recipe.ingredients.map { ing -> [String: Any] in
            var dict: [String: Any] = ["name": ing.name, "displayText": ing.displayText]
            if let qty = ing.quantity { dict["quantity"] = qty }
            if let unit = ing.unit { dict["unit"] = unit.displayName }
            if let prep = ing.preparation { dict["preparation"] = prep }
            dict["available"] = !missing.contains { $0.normalizedName == ing.normalizedName }
            return dict
        }

        let stepList = recipe.orderedSteps.map { step -> [String: Any] in
            var dict: [String: Any] = ["instruction": step.instruction, "index": step.orderIndex]
            if let duration = step.durationMinutes { dict["durationMinutes"] = duration }
            return dict
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "Found recipe '\(recipe.name)'",
            data: [
                "name": recipe.name,
                "description": recipe.descriptionText ?? "",
                "notes": recipe.notes ?? "",
                "cookingTemperature": recipe.cookingTemperature ?? "",
                "ingredients": ingredientList,
                "steps": stepList,
                "missingCount": missing.count,
                "canMake": missing.isEmpty,
                "totalTime": recipe.formattedTotalTime ?? "Unknown",
                "difficulty": recipe.difficulty.displayName,
                "tags": recipe.tags
            ]
        )
    }

    private func recipeCheckAvailability(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        let inventory = Ingredient.list(in: modelContext)
        let missing = recipe.missingIngredients(from: inventory)

        let missingList = missing.map { ingredient -> [String: Any] in
            ["name": ingredient.name, "displayText": ingredient.displayText]
        }

        let canMake = missing.isEmpty
        let message = canMake
            ? "You can make '\(recipe.name)' with current inventory"
            : "Missing \(missing.count) item\(missing.count == 1 ? "" : "s") for '\(recipe.name)'"

        return .success(
            id: call.id,
            name: call.name,
            message: message,
            data: [
                "name": recipe.name,
                "canMake": canMake,
                "missingCount": missing.count,
                "missing": missingList
            ]
        )
    }

    private func recipeDelete(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        let recipeName = recipe.name
        modelContext.delete(recipe)

        return .success(
            id: call.id,
            name: call.name,
            message: "Deleted recipe '\(recipeName)'"
        )
    }

    // MARK: - Helpers

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
