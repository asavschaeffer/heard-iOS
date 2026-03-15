import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import Combine
import VoiceCore

@MainActor
protocol ChatVoiceCoordinating: AnyObject {
    var delegate: VoiceCallCoordinatorDelegate? { get set }
    var onCapturedAudio: ((Data) -> Void)? { get set }
    var onCallKitStartRequested: (() -> Void)? { get set }
    var onCallKitTransactionAccepted: (() -> Void)? { get set }
    var onCallKitPerformStart: (() -> Void)? { get set }
    var onCallKitActivated: (() -> Void)? { get set }
    var onPlaybackStarted: (() -> Void)? { get set }

    func prewarmPlayback()
    func transportWillConnect()
    func startCall()
    func stopCall()
    func toggleMute()
    func toggleSpeaker()
    func transportDidConnect()
    func transportDidDisconnect(autoReconnect: Bool)
    func transportDidFail(message: String)
    func transportDidReceiveAudio(_ data: Data)
}

extension VoiceCallCoordinator: ChatVoiceCoordinating {}

@MainActor
class ChatViewModel: ObservableObject {

    enum ChatConfig {
        static let transcriptDebounceInterval: TimeInterval = 0.9
    }

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    enum ToolCallStatus: Equatable {
        case pending
        case success
        case error
    }

    struct ToolCallDetail: Identifiable, Equatable {
        let key: String
        let value: String

        var id: String { "\(key)|\(value)" }
    }

    struct ToolCallChip: Identifiable, Equatable {
        let id: String
        let functionName: String
        var anchorMessageID: UUID?
        let iconName: String
        let actionText: String
        var status: ToolCallStatus
        var details: [ToolCallDetail]
    }

    // MARK: - Published Properties

    @Published var connectionState: ConnectionState = .disconnected
    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false
    @Published var toolCallChips: [ToolCallChip] = []
    @Published var callState = VoiceCallUIState()
    @Published var callDuration: TimeInterval = 0
    @Published var callKitEnabled = true
    @Published private(set) var isMicrophoneMuted = false
    @Published private(set) var isSpeakerPreferred = true
    @Published var chefExpression: ChefExpression = .pouting
    
    // MARK: - Private Properties

    private var geminiService: GeminiService?
    private var modelContext: ModelContext?
    private let voiceCoordinator: ChatVoiceCoordinating
    private var pendingMessages: [PendingMessage] = []
    private var draftMessageId: UUID?
    private var assistantTranscriptMessageId: UUID?
    private var assistantTranscriptBuffer: String = ""
    private var assistantTextMessageId: UUID?
    private var assistantTextBuffer: String = ""
    private var inputTranscriptBuffer: String = ""
    private var lastTranscriptText: String?
    private var transcriptDebounceWorkItem: DispatchWorkItem?
    private var activeThread: ChatThread?
    private var callTimer: Timer?
    private var callStartDate: Date?
    private var callDurationAccumulated: TimeInterval = 0
    private let liveActivityManager = LiveActivityManager()
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var hasPrewarmedForFirstCall = false
    private var isStoppingVoiceSession = false
    private let callStartupTrace = CallStartupTrace()
    private let makeGeminiService: @MainActor (ModelContext) -> GeminiService
    private let shouldBootstrapThreadOnModelContext: Bool

    private struct PendingMessage {
        let message: ChatMessage
        let text: String?
        let imageData: Data?
    }
    
    // MARK: - Initialization

    var isStoppingCall: Bool { isStoppingVoiceSession }
    var hasScheduledReconnect: Bool { reconnectTask != nil }

    convenience init() {
        self.init(
            geminiServiceFactory: { GeminiService(modelContext: $0) },
            voiceCoordinator: nil,
            shouldBootstrapThreadOnModelContext: true
        )
    }

    init(
        geminiServiceFactory: @escaping @MainActor (ModelContext) -> GeminiService,
        voiceCoordinator: ChatVoiceCoordinating? = nil,
        shouldBootstrapThreadOnModelContext: Bool = true
    ) {
        self.makeGeminiService = geminiServiceFactory
        self.shouldBootstrapThreadOnModelContext = shouldBootstrapThreadOnModelContext
        let initialCallKitEnabled = true
        let coordinator = voiceCoordinator ?? VoiceCallCoordinator(displayName: "Heard, Chef", callKitEnabled: initialCallKitEnabled)
        self.voiceCoordinator = coordinator
        coordinator.delegate = self
        coordinator.onCallKitStartRequested = { [weak self] in
            self?.callStartupTrace.mark(.callKitStartRequested)
        }
        coordinator.onCallKitTransactionAccepted = { [weak self] in
            self?.callStartupTrace.mark(.callKitTransactionAccepted)
        }
        coordinator.onCallKitPerformStart = { [weak self] in
            self?.callStartupTrace.mark(.callKitPerformStart)
        }
        coordinator.onCallKitActivated = { [weak self] in
            self?.callStartupTrace.mark(.callKitActivated)
        }
        coordinator.onPlaybackStarted = { [weak self] in
            self?.callStartupTrace.mark(.playbackStarted)
        }
        coordinator.onCapturedAudio = { [weak self] data in
            self?.callStartupTrace.mark(.firstOutboundAudioSent)
            self?.geminiService?.sendAudio(data: data)
        }
    }

    deinit {
        callTimer?.invalidate()
        reconnectTask?.cancel()
    }

    func setModelContext(_ context: ModelContext) {
        if modelContext == nil {
            modelContext = context
        }
        if geminiService == nil {
            // ChatView can reappear during sheet/tab transitions; preserve the same client so
            // in-flight REST turns are not orphaned by a fresh GeminiService instance.
            let service = makeGeminiService(modelContext ?? context)
            service.delegate = self
            geminiService = service
        }
        guard shouldBootstrapThreadOnModelContext else { return }
        loadOrCreateThread()
    }

    func prepareForFirstCall() {
        guard !hasPrewarmedForFirstCall else { return }
        hasPrewarmedForFirstCall = true
        voiceCoordinator.prewarmPlayback()
        VoiceDiagnostics.audio("[Perf] Shared playback stack prepared for first call")
    }

    func noteCallPresentationRequested() {
        callStartupTrace.begin()
    }

    func noteCallScreenPresented() {
        callStartupTrace.ensureStarted()
        callStartupTrace.mark(.callViewPresented)
    }

    private func loadOrCreateThread() {
        guard let context = modelContext else { return }
        if activeThread != nil { return }

        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.title == "Heard, Chef" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let existingThread = (try? context.fetch(descriptor))?.first
        let thread = existingThread ?? ChatThread(title: "Heard, Chef")
        if existingThread == nil {
            context.insert(thread)
            let greeting = ChatMessage(role: .assistant, text: "What are we cooking today?", thread: thread)
            greeting.expression = .joyful
            context.insert(greeting)
        }

        activeThread = thread
        migrateMessagesIfNeeded()
        fetchMessages()
    }

    private func fetchMessages() {
        guard let context = modelContext, let thread = activeThread else { return }
        let threadId = thread.id
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.thread?.id == threadId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        messages = (try? context.fetch(descriptor)) ?? []
    }

    private func migrateMessagesIfNeeded() {
        guard let context = modelContext, let thread = activeThread else { return }
        guard !messages.isEmpty, thread.messages.isEmpty else { return }
        for message in messages {
            message.thread = thread
            context.insert(message)
        }
    }

    private func applyVoiceState(_ newState: VoiceCallUIState) {
        var mergedState = newState
        // Video presentation is owned by ChatViewModel/UI, not VoiceCallCoordinator.
        mergedState.isVideoStreaming = callState.isVideoStreaming
        mergedState.videoFrameInterval = callState.videoFrameInterval

        callState = mergedState
        isMicrophoneMuted = mergedState.isMicrophoneMuted
        isSpeakerPreferred = mergedState.isSpeakerPreferred
    }

    private func startCallTimer() {
        if callStartDate == nil {
            callStartDate = Date()
        }
        callTimer?.invalidate()
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.updateCallDuration()
            }
        }
        updateCallDuration()
    }

    private func pauseCallTimer() {
        if let start = callStartDate {
            callDurationAccumulated += Date().timeIntervalSince(start)
        }
        callStartDate = nil
        callTimer?.invalidate()
        callTimer = nil
        updateCallDuration()
    }

    private func resetCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
        callStartDate = nil
        callDurationAccumulated = 0
        callDuration = 0
    }

    private func updateCallDuration() {
        let active = callStartDate.map { Date().timeIntervalSince($0) } ?? 0
        callDuration = callDurationAccumulated + active
        // TODO: Update Live Activity with call status/duration.
        liveActivityManager.updateCallActivity(status: connectionStateLabel, duration: callDuration)
    }

    var callDurationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = callDuration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: callDuration) ?? "0:00"
    }

    private var connectionStateLabel: String {
        switch connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Reconnecting"
        case .error:
            return "Connection issue"
        }
    }

    private func sendCallHaptic(style: UINotificationFeedbackGenerator.FeedbackType) {
        SharedHaptics.generator.prepare()
        SharedHaptics.generator.notificationOccurred(style)
    }

    private func resetReconnectBackoff() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectDelay = 1.0
    }

    private func scheduleAudioReconnect() {
        guard callState.isPresented else { return }

        reconnectTask?.cancel()
        let delay = reconnectDelay
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.callState.isPresented else { return }
                self.connect(mode: .audio)
            }
        }

        reconnectDelay = min(reconnectDelay * 2.0, maxReconnectDelay)
        VoiceDiagnostics.audio("[Audio] Scheduled Gemini reconnect delay=\(String(format: "%.1f", delay))s")
    }

    // MARK: - Actions

    /// Connect Gemini Live WebSocket with the requested session mode.
    func connect(mode: SessionMode = .audio) {
        guard connectionState != .connecting else { return }
        connectionState = .connecting
        voiceCoordinator.transportWillConnect()
        let config: SessionConfig = {
            switch mode {
            case .audio:
                return .audio(profile: ChatSettings.currentAudioProfile())
            case .text:
                return .text()
            }
        }()
        geminiService?.connect(config: config)
    }
    
    func disconnect() {
        stopVoiceSession()
    }

    func sendMessage(_ text: String) {
        sendMessage(text, attachment: nil)
    }

    func sendMessage(_ text: String, attachment: ChatAttachment?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty
        guard hasText || attachment != nil else { return }

        let message = buildMessage(text: hasText ? trimmed : nil, attachment: attachment)
        insertMessage(message)
        messages.append(message)

        enqueueOrSend(
            text: textPayload(for: message, originalText: hasText ? trimmed : nil),
            imageData: message.imageData,
            message: message
        )
    }
    
    func retryMessage(_ message: ChatMessage) {
        guard message.role.isUser, message.status == .failed else { return }
        message.markStatus(.sending)
        let text = message.text
        let imageData = message.imageData
        enqueueOrSend(text: text, imageData: imageData, message: message)
        activeThread?.touch()
    }

    // MARK: - Voice Session Management

    func startVoiceSession() {
        isStoppingVoiceSession = false
        callStartupTrace.ensureStarted()
        callStartupTrace.mark(.voiceSessionStarted)
        let wasPresented = callState.isPresented
        voiceCoordinator.startCall()
        // TODO: Start Live Activity when Dynamic Island is implemented.
        liveActivityManager.startCallActivity(displayName: "Heard, Chef")
        if connectionState != .connecting && connectionState != .connected {
            connect(mode: .audio)
        }
        if !wasPresented {
            updateCallDuration()
        }
    }

    func stopVoiceSession() {
        guard !isStoppingVoiceSession else { return }
        isStoppingVoiceSession = true
        callStartupTrace.finish(reason: "stopped")
        let wasPresented = callState.isPresented
        let hasActiveSocketSession = geminiService?.hasActiveSocketSession == true
        voiceCoordinator.stopCall()
        // TODO: End Live Activity when Dynamic Island is implemented.
        liveActivityManager.endCallActivity()
        resetReconnectBackoff()
        stopVideoStreaming()
        cancelTranscriptDebounce()
        finalizeDraftIfNeeded()
        finalizeAssistantStreamingMessages()
        inputTranscriptBuffer = ""
        resetCallTimer()
        // Disconnect the audio session; next text send will lazy-reconnect in text mode
        geminiService?.disconnect(reason: "stopVoiceSession")
        if !hasActiveSocketSession {
            finalizeTransportDisconnect(shouldAutoReconnect: false)
        }
        if wasPresented {
            sendCallHaptic(style: .warning)
        }
    }
    
    func toggleMute() {
        voiceCoordinator.toggleMute()
    }

    func toggleSpeaker() {
        voiceCoordinator.toggleSpeaker()
    }

    // MARK: - Queueing
    
    private func insertMessage(_ message: ChatMessage) {
        guard let context = modelContext else { return }
        if message.thread == nil {
            message.thread = activeThread
        }
        context.insert(message)
        activeThread?.touch()
    }

    private func enqueueOrSend(text: String?, imageData: Data?, message: ChatMessage) {
        if let mediaType = message.mediaType {
            print("[Chat] enqueueOrSend media message id=\(message.id.uuidString.prefix(8)) type=\(mediaType.rawValue) file=\(message.mediaFilename ?? "none") imageBytes=\(message.imageData?.count ?? 0)")
        } else {
            print("[Chat] enqueueOrSend text message id=\(message.id.uuidString.prefix(8)) chars=\(text?.count ?? 0)")
        }
        // During a call, route through WebSocket (may need to queue if connecting)
        if callState.isPresented {
            if connectionState == .connected {
                sendToGemini(text: text, imageData: imageData, message: message)
            } else {
                // Queue for when WebSocket connects
                pendingMessages.append(PendingMessage(message: message, text: text, imageData: imageData))
                print("[Chat] queued pending message id=\(message.id.uuidString.prefix(8)) pendingCount=\(pendingMessages.count)")
                if connectionState == .disconnected {
                    connect(mode: .audio)
                }
            }
            return
        }

        // Not in a call — send directly via REST (GeminiService routes automatically)
        sendToGemini(text: text, imageData: imageData, message: message)
    }

    private func flushPendingMessages() {
        guard connectionState == .connected else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        print("[Chat] flushing pending messages count=\(queued.count)")
        for item in queued {
            sendToGemini(text: item.text, imageData: item.imageData, message: item.message)
        }
    }

    private func sendToGemini(text: String?, imageData: Data?, message: ChatMessage) {
        // Keep message status as .sending initially (set on buildMessage)
        let result: Result<Void, Error>
        let path = callState.isPresented ? "websocket-call" : "rest-chat"
        print("[Chat] sendToGemini start id=\(message.id.uuidString.prefix(8)) path=\(path) textChars=\(text?.count ?? 0) imageBytes=\(imageData?.count ?? 0) mediaType=\(message.mediaType?.rawValue ?? "none")")

        if let text = text, let imageData = imageData, message.mediaType == .image {
            result = geminiService?.sendTextWithPhoto(text, imageData: imageData, messageID: message.id) ?? .failure(GeminiError.serviceUnavailable)
        } else if let text = text {
            result = geminiService?.sendText(text, messageID: message.id) ?? .failure(GeminiError.serviceUnavailable)
        } else if let imageData = imageData, message.mediaType == .image {
            result = geminiService?.sendPhoto(imageData, messageID: message.id) ?? .failure(GeminiError.serviceUnavailable)
        } else {
            result = .success(())
        }

        // Only mark failed if result is failure; leave .sending otherwise
        if case .failure = result {
            message.markStatus(.failed)
            print("[Chat] sendToGemini failed id=\(message.id.uuidString.prefix(8))")
        } else {
            print("[Chat] sendToGemini dispatched id=\(message.id.uuidString.prefix(8))")
        }

        if let url = ChatAttachmentPathResolver.resolveURL(
            storedReference: message.mediaURL,
            fallbackFilename: message.mediaFilename
        ) {
            if message.mediaType == .video {
                print("[Chat] forwarding video attachment to Gemini service id=\(message.id.uuidString.prefix(8)) file=\(message.mediaFilename ?? url.lastPathComponent)")
                geminiService?.sendVideoAttachment(url: url, utType: message.mediaUTType)
            } else if message.mediaType == .document {
                print("[Chat] forwarding document attachment to Gemini service id=\(message.id.uuidString.prefix(8)) file=\(message.mediaFilename ?? url.lastPathComponent)")
                geminiService?.sendDocumentAttachment(url: url, utType: message.mediaUTType)
            }
        }
        activeThread?.touch()
    }

    private func buildMessage(text: String?, attachment: ChatAttachment?) -> ChatMessage {
        switch attachment?.kind {
        case .image:
            return ChatMessage(
                role: .user,
                text: text,
                imageData: attachment?.imageData,
                mediaType: .image,
                status: .sending
            )
        case .video:
            return ChatMessage(
                role: .user,
                text: text,
                imageData: attachment?.imageData,
                mediaType: .video,
                mediaURL: storedMediaReference(for: attachment),
                mediaFilename: attachment?.filename,
                mediaUTType: attachment?.utType,
                status: .sending
            )
        case .pdf, .document:
            return ChatMessage(
                role: .user,
                text: text,
                mediaType: .document,
                mediaURL: storedMediaReference(for: attachment),
                mediaFilename: attachment?.filename,
                mediaUTType: attachment?.utType,
                status: .sending
            )
        case .none:
            return ChatMessage(
                role: .user,
                text: text,
                status: .sending
            )
        }
    }

    private func storedMediaReference(for attachment: ChatAttachment?) -> String? {
        ChatAttachmentPathResolver.storedReference(
            for: attachment?.fileURL,
            filename: attachment?.filename
        )
    }

    private func textPayload(for message: ChatMessage, originalText: String?) -> String? {
        if let originalText {
            return originalText
        }

        guard let mediaType = message.mediaType else { return nil }
        let filename = message.mediaFilename ?? "attachment"
        switch mediaType {
        case .video:
            return "Attached a video: \(filename)"
        case .document:
            if let utType = message.mediaUTType, UTType(utType)?.conforms(to: .pdf) == true {
                return "Attached a PDF: \(filename)"
            }
            return "Attached a document: \(filename)"
        case .image, .audio:
            return nil
        }
    }

    private func markPendingMessagesFailed() {
        for pending in pendingMessages {
            pending.message.markStatus(.failed)
        }
        pendingMessages.removeAll()
    }

    private func markLatestUserMessageRead() {
        guard let latest = messages.last(where: { $0.role.isUser }) else { return }
        if latest.status != .read {
            latest.markStatus(.read)
        }
    }

    private func markLatestUserMessageSent() {
        guard let latest = messages.last(where: { $0.role.isUser && $0.status == .sending }) else { return }
        latest.markStatus(.sent)
        print("[Chat] Marked latest user message as Sent")
    }
    
    private func markLatestUserMessageFailedIfSending() {
        guard let latest = messages.last(where: { $0.role.isUser && $0.status == .sending }) else { return }
        latest.markStatus(.failed)
        print("[Chat] Marked latest user message as Failed")
    }

    private func startToolCallChip(id: String, name: String, arguments: [String: Any]) {
        let pending = ToolCallChip(
            id: id,
            functionName: name,
            anchorMessageID: nil,
            iconName: toolDomainIconName(functionName: name),
            actionText: actionDescription(functionName: name, arguments: arguments),
            status: .pending,
            details: []
        )
        if let index = toolCallChips.firstIndex(where: { $0.id == id }) {
            toolCallChips[index] = pending
        } else {
            toolCallChips.append(pending)
            if toolCallChips.count > 16 {
                toolCallChips.removeFirst(toolCallChips.count - 16)
            }
        }
    }

    private func finishToolCallChip(name: String, result: FunctionResult) {
        let isSuccess = (result.response["success"] as? Bool) == true
        let details = detailItems(from: result.response)

        if let index = toolCallChips.firstIndex(where: { $0.id == result.id }) {
            toolCallChips[index].status = isSuccess ? .success : .error
            toolCallChips[index].details = details
        } else {
            toolCallChips.append(
                ToolCallChip(
                    id: result.id,
                    functionName: name,
                    anchorMessageID: nil,
                    iconName: toolDomainIconName(functionName: name),
                    actionText: actionDescription(functionName: name, arguments: [:]),
                    status: isSuccess ? .success : .error,
                    details: details
                )
            )
        }
    }

    private func toolDomainIconName(functionName: String) -> String {
        if functionName.contains("ingredient") {
            return "refrigerator.fill"
        }
        if functionName.contains("recipe") {
            return "fork.knife.circle.fill"
        }
        return "gearshape.fill"
    }

    private func actionDescription(functionName: String, arguments: [String: Any]) -> String {
        switch functionName {
        case "search_ingredients", "search_recipes":
            return "Search: \(quoted(arguments["query"]))"
        case "get_ingredient", "get_recipe":
            return "View: \(quoted(arguments["name"]))"
        case "list_ingredients", "list_recipes":
            return "List"
        case "add_ingredient":
            return "Add: \(quoted(arguments["name"]))"
        case "remove_ingredient":
            return "Remove: \(quoted(arguments["name"]))"
        case "update_ingredient":
            return "Update: \(quoted(arguments["name"]))"
        case "create_recipe":
            return "Create: \(quoted(arguments["name"]))"
        case "update_recipe":
            return "Update recipe: \(quoted(arguments["name"]))"
        case "delete_recipe":
            return "Delete recipe: \(quoted(arguments["name"]))"
        case "suggest_recipes":
            return "Suggest recipes"
        case "check_recipe_availability":
            return "Check availability: \(quoted(arguments["name"]))"
        default:
            return functionName
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private func quoted(_ value: Any?) -> String {
        if let string = value as? String, !string.isEmpty {
            return "\"\(string)\""
        }
        return "item"
    }

    private func attachUnanchoredToolChips(to messageID: UUID) {
        for index in toolCallChips.indices where toolCallChips[index].anchorMessageID == nil {
            toolCallChips[index].anchorMessageID = messageID
        }
    }

    private func detailItems(from response: [String: Any]) -> [ToolCallDetail] {
        var details: [ToolCallDetail] = []
        for key in response.keys.sorted() {
            if key == "success" { continue }
            appendDetailItems(value: response[key] as Any, path: [key], into: &details)
        }
        return details
    }

    private func appendDetailItems(value: Any, path: [String], into details: inout [ToolCallDetail]) {
        if let map = value as? [String: Any] {
            if map.isEmpty {
                details.append(ToolCallDetail(key: makeDetailTitle(path), value: "None"))
                return
            }
            for key in map.keys.sorted() {
                appendDetailItems(value: map[key] as Any, path: path + [key], into: &details)
            }
            return
        }

        if let array = value as? [Any] {
            if array.isEmpty {
                details.append(ToolCallDetail(key: makeDetailTitle(path), value: "None"))
                return
            }

            let scalarValues = array.compactMap { formattedScalar($0) }
            if scalarValues.count == array.count {
                details.append(
                    ToolCallDetail(
                        key: makeDetailTitle(path),
                        value: scalarValues.joined(separator: ", ")
                    )
                )
                return
            }

            for (index, item) in array.enumerated() {
                appendDetailItems(value: item, path: path + ["\(index + 1)"], into: &details)
            }
            return
        }

        let scalar = formattedScalar(value) ?? String(describing: value)
        details.append(ToolCallDetail(key: makeDetailTitle(path), value: scalar))
    }

    private func formattedScalar(_ value: Any) -> String? {
        if value is NSNull {
            return "None"
        }
        if let text = value as? String {
            return text
        }
        if let bool = value as? Bool {
            return bool ? "Yes" : "No"
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let double = value as? Double {
            return numberFormatter.string(from: NSNumber(value: double)) ?? "\(double)"
        }
        if let number = value as? NSNumber {
            return numberFormatter.string(from: number) ?? number.stringValue
        }
        return nil
    }

    private func makeDetailTitle(_ path: [String]) -> String {
        path.map(humanizeDetailSegment).joined(separator: " > ")
    }

    private func humanizeDetailSegment(_ segment: String) -> String {
        if Int(segment) != nil {
            return "Item \(segment)"
        }
        return segment
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter
    }

    // MARK: - Transcript Handling

    private func updateDraftMessage(text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal && trimmed.isEmpty {
            clearDraftMessage()
            return
        }

        if let draftId = draftMessageId, let index = messages.firstIndex(where: { $0.id == draftId }) {
            let message = messages[index]
            let draftText = trimmed.isEmpty ? text : trimmed
            message.updateText(draftText, isDraft: !isFinal)
        } else {
            let draftText = trimmed.isEmpty ? text : trimmed
            let newDraft = ChatMessage(
                role: .user,
                text: draftText,
                status: .sent,
                isDraft: !isFinal
            )
            insertMessage(newDraft)
            messages.append(newDraft)
            draftMessageId = newDraft.id
        }

        if isFinal { draftMessageId = nil }
    }

    private func clearDraftMessage() {
        if let draftId = draftMessageId, let index = messages.firstIndex(where: { $0.id == draftId }) {
            let message = messages[index]
            messages.remove(at: index)
            if let context = modelContext {
                context.delete(message)
            }
        }
        draftMessageId = nil
    }

    private func finalizeDraftIfNeeded() {
        cancelTranscriptDebounce()
        guard let draftId = draftMessageId,
              messages.firstIndex(where: { $0.id == draftId }) != nil else {
            return
        }

        let text = lastTranscriptText ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearDraftMessage()
            return
        }

        updateDraftMessage(text: trimmed, isFinal: true)
        lastTranscriptText = nil
        inputTranscriptBuffer = ""
    }

    private func mergeStreamingText(existing: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return existing }
        if existing.isEmpty { return incoming }
        if incoming.hasPrefix(existing) { return incoming }
        if existing.hasSuffix(incoming) { return existing }
        return existing + incoming
    }

    private static let feelingRegex = try! NSRegularExpression(pattern: #"\[feeling:(\w+)\]"#)

    private func stripFeelingTag(from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        if let match = Self.feelingRegex.firstMatch(in: text, range: range),
           let captureRange = Range(match.range(at: 1), in: text),
           let expr = ChefExpression(rawValue: String(text[captureRange])) {
            chefExpression = expr
        }
        return Self.feelingRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func updateAssistantTranscriptMessage(chunk: String, isFinal: Bool) {
        guard !chunk.isEmpty else { return }

        assistantTranscriptBuffer = mergeStreamingText(existing: assistantTranscriptBuffer, incoming: chunk)
        let stripped = stripFeelingTag(from: assistantTranscriptBuffer)
        let text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let messageId = assistantTranscriptMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].updateText(text, isDraft: !isFinal)
            messages[index].expression = chefExpression
            attachUnanchoredToolChips(to: messageId)
        } else {
            let message = ChatMessage(role: .assistant, text: text, status: .sent, isDraft: !isFinal)
            message.expression = chefExpression
            insertMessage(message)
            messages.append(message)
            assistantTranscriptMessageId = message.id
            attachUnanchoredToolChips(to: message.id)
        }

        if isFinal {
            assistantTranscriptMessageId = nil
            assistantTranscriptBuffer = ""
        }
    }

    private func updateAssistantTextMessage(chunk: String, isFinal: Bool) {
        guard !chunk.isEmpty else { return }

        assistantTextBuffer = mergeStreamingText(existing: assistantTextBuffer, incoming: chunk)
        let stripped = stripFeelingTag(from: assistantTextBuffer)
        let text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let messageId = assistantTextMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].updateText(text, isDraft: !isFinal)
            messages[index].expression = chefExpression
            attachUnanchoredToolChips(to: messageId)
        } else {
            let message = ChatMessage(role: .assistant, text: text, status: .sent, isDraft: !isFinal)
            message.expression = chefExpression
            insertMessage(message)
            messages.append(message)
            assistantTextMessageId = message.id
            attachUnanchoredToolChips(to: message.id)
        }

        if isFinal {
            assistantTextMessageId = nil
            assistantTextBuffer = ""
        }
    }

    private func finalizeAssistantStreamingMessages() {
        if let messageId = assistantTranscriptMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            let finalText = stripFeelingTag(from: assistantTranscriptBuffer)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if finalText.isEmpty {
                let message = messages.remove(at: index)
                modelContext?.delete(message)
            } else {
                messages[index].updateText(finalText, isDraft: false)
                messages[index].expression = chefExpression
            }
        }
        assistantTranscriptMessageId = nil
        assistantTranscriptBuffer = ""

        if let messageId = assistantTextMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            let finalText = stripFeelingTag(from: assistantTextBuffer)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if finalText.isEmpty {
                let message = messages.remove(at: index)
                modelContext?.delete(message)
            } else {
                messages[index].updateText(finalText, isDraft: false)
                messages[index].expression = chefExpression
            }
        }
        assistantTextMessageId = nil
        assistantTextBuffer = ""
    }

    private func scheduleTranscriptFinalize() {
        cancelTranscriptDebounce()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.finalizeDraftIfNeeded()
            }
        }
        transcriptDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + ChatConfig.transcriptDebounceInterval, execute: workItem)
    }

    private func cancelTranscriptDebounce() {
        transcriptDebounceWorkItem?.cancel()
        transcriptDebounceWorkItem = nil
    }

    // MARK: - Video Streaming (Stub)

    func startVideoStreaming(with cameraService: CameraService) {
        callState.isVideoStreaming = true

        cameraService.setVideoFrameHandler(frameInterval: callState.videoFrameInterval) { [weak self] data in
            Task { @MainActor in
                self?.geminiService?.sendVideoFrame(data)
            }
        }

        cameraService.startVideoFrameStreaming()
    }

    func stopVideoStreaming() {
        callState.isVideoStreaming = false
    }

    func toggleVideoFromCallView() {
        callState.isVideoStreaming.toggle()
    }
}

// MARK: - Delegate

extension ChatViewModel: GeminiServiceDelegate {
    func geminiServiceDidConnect(_ service: GeminiService) {
        callStartupTrace.mark(.transportConnected)
        connectionState = .connected
        voiceCoordinator.transportDidConnect()
        resetReconnectBackoff()
        flushPendingMessages()
        if callState.isPresented {
            startCallTimer()
            sendCallHaptic(style: .success)
        }
    }

    func geminiServiceDidDisconnect(_ service: GeminiService) {
        let shouldAutoReconnect = isStoppingVoiceSession == false && {
            if case .error = connectionState { return false }
            return true
        }()
        finalizeTransportDisconnect(shouldAutoReconnect: shouldAutoReconnect)
    }

    func geminiService(_ service: GeminiService, didReceiveError error: Error) {
        callStartupTrace.fail(message: error.localizedDescription)
        connectionState = .error(error.localizedDescription)
        voiceCoordinator.transportDidFail(message: error.localizedDescription)
        isTyping = false
        finalizeAssistantStreamingMessages()
        markPendingMessagesFailed()
        markLatestUserMessageFailedIfSending()
        if callState.isPresented {
            pauseCallTimer()
        }
    }

    func geminiService(_ service: GeminiService, didReceiveTranscript transcript: String, isFinal: Bool) {
        if isFinal {
            VoiceDiagnostics.gemini("[Gemini] Output transcript final: \(transcript)")
        }
        // Output transcript: what the AI said (speech-to-text of AI audio)
        // In audio mode, show as assistant message so user can read it
        guard geminiService?.currentMode == .audio else { return }
        updateAssistantTranscriptMessage(chunk: transcript, isFinal: isFinal)
        markLatestUserMessageRead()
    }

    func geminiService(_ service: GeminiService, didReceiveInputTranscript transcript: String, isFinal: Bool) {
        if isFinal {
            VoiceDiagnostics.gemini("[Gemini] Input transcript final: \(transcript)")
        }
        // Input transcript: what the user said (speech-to-text of user audio)
        inputTranscriptBuffer = mergeStreamingText(existing: inputTranscriptBuffer, incoming: transcript)
        lastTranscriptText = inputTranscriptBuffer
        updateDraftMessage(text: inputTranscriptBuffer, isFinal: isFinal)
        if isFinal {
            cancelTranscriptDebounce()
            inputTranscriptBuffer = ""
        } else {
            scheduleTranscriptFinalize()
        }
    }

    func geminiService(_ service: GeminiService, didReceiveResponse text: String) {
        let preview = text.count > 160 ? String(text.prefix(160)) + "..." : text
        VoiceDiagnostics.gemini("[Gemini] Response text received chars=\(text.count) preview=\(preview)")
        updateAssistantTextMessage(chunk: text, isFinal: false)
        markLatestUserMessageRead()
        service.notifyCurrentSendResult()
    }

    func geminiService(_ service: GeminiService, didReceiveAudio data: Data) {
        callStartupTrace.mark(.firstAudioReceived)
        VoiceDiagnostics.gemini("[Gemini] Response audio received bytes=\(data.count)")
        finalizeDraftIfNeeded()
        voiceCoordinator.transportDidReceiveAudio(data)
        markLatestUserMessageRead()
        service.notifyCurrentSendResult()
    }

    func geminiService(_ service: GeminiService, didStartFunctionCall id: String, name: String, arguments: [String: Any]) {
        startToolCallChip(id: id, name: name, arguments: arguments)
    }

    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: FunctionResult) {
        finishToolCallChip(name: name, result: result)
        service.notifyCurrentSendResult()
    }

    func geminiServiceDidStartResponse(_ service: GeminiService) {
        isTyping = true
        finalizeAssistantStreamingMessages()
        assistantTranscriptMessageId = nil
        assistantTranscriptBuffer = ""
        assistantTextMessageId = nil
        assistantTextBuffer = ""
        markLatestUserMessageSent()
    }

    func geminiServiceDidEndResponse(_ service: GeminiService) {
        isTyping = false
        finalizeAssistantStreamingMessages()
        markLatestUserMessageRead()
    }
}

extension ChatViewModel: VoiceCallCoordinatorDelegate {
    func voiceCallCoordinator(_ coordinator: VoiceCallCoordinator, didUpdate state: VoiceCallUIState) {
        applyVoiceState(state)
    }

    func voiceCallCoordinator(_ coordinator: VoiceCallCoordinator, didChangeCallKitEnabled isEnabled: Bool) {
        callKitEnabled = isEnabled
    }
}

@MainActor
private extension ChatViewModel {
    func finalizeTransportDisconnect(shouldAutoReconnect: Bool) {
        finalizeAssistantStreamingMessages()
        connectionState = .disconnected
        voiceCoordinator.transportDidDisconnect(autoReconnect: shouldAutoReconnect)
        isTyping = false
        if callState.isPresented {
            pauseCallTimer()
            if shouldAutoReconnect {
                scheduleAudioReconnect()
            }
        }
        isStoppingVoiceSession = false
    }
}

@MainActor
private final class CallStartupTrace {
    enum Phase: String {
        case callViewPresented = "call-ui-presented"
        case voiceSessionStarted = "voice-session-started"
        case callKitStartRequested = "callkit-start-requested"
        case callKitTransactionAccepted = "callkit-transaction-accepted"
        case callKitPerformStart = "callkit-perform-start"
        case callKitActivated = "callkit-activated"
        case transportConnected = "transport-connected"
        case firstOutboundAudioSent = "first-outbound-audio-sent"
        case firstAudioReceived = "first-audio-received"
        case playbackStarted = "playback-started"
    }

    private var startedAt: Date?
    private var previousPhaseAt: Date?
    private var recordedPhases: Set<Phase> = []

    func begin() {
        startedAt = .now
        previousPhaseAt = startedAt
        recordedPhases.removeAll()
        VoiceDiagnostics.audio("[Perf] Call startup phase=begin totalMs=0 stepMs=0")
    }

    func ensureStarted() {
        if startedAt == nil {
            begin()
        }
    }

    func mark(_ phase: Phase) {
        guard let startedAt, !recordedPhases.contains(phase) else { return }

        let now = Date.now
        let totalMs = milliseconds(from: startedAt, to: now)
        let stepMs = milliseconds(from: previousPhaseAt ?? startedAt, to: now)
        VoiceDiagnostics.audio("[Perf] Call startup phase=\(phase.rawValue) totalMs=\(totalMs) stepMs=\(stepMs)")
        previousPhaseAt = now
        recordedPhases.insert(phase)

        if phase == .playbackStarted {
            finish(reason: "complete")
        }
    }

    func fail(message: String) {
        guard let startedAt else { return }
        let totalMs = milliseconds(from: startedAt, to: .now)
        VoiceDiagnostics.audio("[Perf] Call startup phase=failed totalMs=\(totalMs) message=\(message)")
    }

    func finish(reason: String) {
        guard let startedAt else { return }
        let totalMs = milliseconds(from: startedAt, to: .now)
        VoiceDiagnostics.audio("[Perf] Call startup phase=finish totalMs=\(totalMs) reason=\(reason)")
        self.startedAt = nil
        previousPhaseAt = nil
        recordedPhases.removeAll()
    }

    private func milliseconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1000).rounded())
    }
}
