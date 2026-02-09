import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Combine

@MainActor
class ChatViewModel: ObservableObject {

    enum ChatConfig {
        static let transcriptDebounceInterval: TimeInterval = 0.9
    }

    struct CallSessionState {
        var isPresented = false
        var isListening = false
        var isSpeaking = false
        var audioLevel: Float = 0.0
        var isVideoStreaming = false
        var videoFrameInterval: TimeInterval = 0.2
    }

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Published Properties

    @Published var connectionState: ConnectionState = .disconnected
    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false
    @Published var callState = CallSessionState()
    @Published var callDuration: TimeInterval = 0
    @Published var callKitEnabled = true
    
    // MARK: - Private Properties

    private var geminiService: GeminiService?
    private var modelContext: ModelContext?
    private var audioEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private var playbackNode: AVAudioPlayerNode?
    private var playbackFormat: AVAudioFormat?
    private var pendingAudioChunks: [Data] = []
    private var pendingMessages: [PendingMessage] = []
    private var isPlayingAudio = false
    private var draftMessageId: UUID?
    private var lastTranscriptText: String?
    private var transcriptDebounceWorkItem: DispatchWorkItem?
    private var pendingVoiceStart = false
    private var activeThread: ChatThread?
    private var audioObservers: [NSObjectProtocol] = []
    private var callTimer: Timer?
    private var callStartDate: Date?
    private var callDurationAccumulated: TimeInterval = 0
    private var callKitManager: CallKitManager?
    private let liveActivityManager = LiveActivityManager()

    private struct PendingMessage {
        let message: ChatMessage
        let text: String?
        let imageData: Data?
    }
    
    // MARK: - Initialization

    init() {
        if callKitEnabled {
            setupCallKit()
        } else {
            setupAudioSession()
        }
        observeAudioSession()
    }

    deinit {
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioObservers.removeAll()
        callTimer?.invalidate()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.geminiService = GeminiService(modelContext: context)
        self.geminiService?.delegate = self
        loadOrCreateThread()
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

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("Audio Session Error: \(error)")
        }
    }

    private func setupCallKit() {
        let manager = CallKitManager(appName: "Heard, Chef")
        manager.onStartAudio = { [weak self] in
            self?.configureAudioSessionForCall()
            self?.startAudioCapture()
            self?.callState.isListening = true
        }
        manager.onStopAudio = { [weak self] in
            self?.stopAudioCapture()
            self?.callState.isListening = false
        }
        manager.onMuteChanged = { [weak self] isMuted in
            guard let self else { return }
            self.callState.isListening = !isMuted
            if isMuted {
                self.stopAudioCapture()
            } else {
                self.startAudioCapture()
            }
        }
        callKitManager = manager
    }

    private func configureAudioSessionForCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("Audio Session Error: \(error)")
        }
    }

    private func preferSpeaker() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            print("Audio Session override error: \(error)")
        }
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
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(style)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleRouteChange(note)
            }
        })

        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleInterruption(note)
            }
        })
    }

    private func handleRouteChange(_ notification: Notification) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        if !callKitEnabled {
            callState.isListening = audioEngine?.isRunning == true && !outputs.isEmpty
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            if !callKitEnabled {
                stopAudioCapture()
            }
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            if options.contains(.shouldResume) && callState.isPresented {
                if !callKitEnabled {
                    startAudioCapture()
                    callState.isListening = true
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Actions

    /// Connect WebSocket for audio mode (voice calls only). Text uses REST.
    func connect(mode: SessionMode = .audio) {
        guard connectionState != .connecting else { return }
        connectionState = .connecting
        geminiService?.connect(config: .audio())
    }
    
    func disconnect() {
        stopVoiceSession()
        geminiService?.disconnect()
        connectionState = .disconnected
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
        let wasPresented = callState.isPresented
        callState.isPresented = true
        // TODO: Start Live Activity when Dynamic Island is implemented.
        liveActivityManager.startCallActivity(displayName: "Heard, Chef")
        if callKitEnabled {
            callKitManager?.startCall(displayName: "Heard, Chef")
        }
        // Connect WebSocket for audio
        if connectionState != .connecting && connectionState != .connected {
            connect(mode: .audio)
        }
        
        if connectionState == .connected {
            if !callKitEnabled {
                preferSpeaker()
                startAudioCapture()
                callState.isListening = true
            }
            pendingVoiceStart = false
        } else {
            pendingVoiceStart = true
        }
        
        if !wasPresented {
            updateCallDuration()
        }
    }

    func stopVoiceSession() {
        let wasPresented = callState.isPresented
        callState.isPresented = false
        // TODO: End Live Activity when Dynamic Island is implemented.
        liveActivityManager.endCallActivity()
        if callKitEnabled {
            callKitManager?.endCall()
        } else {
            stopAudioCapture()
            callState.isListening = false
        }
        pendingVoiceStart = false
        stopVideoStreaming()
        cancelTranscriptDebounce()
        finalizeDraftIfNeeded()
        resetCallTimer()
        // Disconnect the audio session; next text send will lazy-reconnect in text mode
        geminiService?.disconnect()
        connectionState = .disconnected
        if wasPresented {
            sendCallHaptic(style: .warning)
        }
    }
    
    func toggleMute() {
        callState.isListening.toggle()
        if callState.isListening {
            startAudioCapture()
        } else {
            stopAudioCapture()
        }
    }

    // MARK: - Audio Engine

    private func startAudioCapture() {
        // Prevent double start
        if audioEngine?.isRunning == true { return }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Audio Engine Start Error: \(error)")
        }
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        callState.audioLevel = 0
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. Visuals
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        var sum: Float = 0
        for i in 0..<frameLength { sum += abs(channelData[i]) }
        let average = sum / Float(frameLength)
        
        Task { @MainActor in
            self.callState.audioLevel = min(1.0, average * 10)
        }

        // 2. Stream to Gemini
        let pcmData = convertToPCM16(buffer: buffer)
        geminiService?.sendAudio(data: pcmData)
    }

    private func convertToPCM16(buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.floatChannelData?[0] else { return Data() }
        let frameLength = Int(buffer.frameLength)
        var pcmData = Data(capacity: frameLength * 2)
        
        for i in 0..<frameLength {
            let sample = Int16(max(-1, min(1, channelData[i])) * Float(Int16.max))
            withUnsafeBytes(of: sample.littleEndian) { pcmData.append(contentsOf: $0) }
        }
        return pcmData
    }

    // MARK: - Audio Playback

    private func playAudio(data: Data) {
        guard !data.isEmpty else { return }
        setupPlaybackEngineIfNeeded()
        pendingAudioChunks.append(data)

        if !isPlayingAudio {
            isPlayingAudio = true
            playNextAudioChunk()
        }
    }

    private func playNextAudioChunk() {
        guard let next = pendingAudioChunks.first else {
            isPlayingAudio = false
            callState.isSpeaking = false
            return
        }

        pendingAudioChunks.removeFirst()
        guard let buffer = makePCMBuffer(from: next) else {
            playNextAudioChunk()
            return
        }

        if playbackNode?.isPlaying == false {
            playbackNode?.play()
        }

        callState.isSpeaking = true
        playbackNode?.scheduleBuffer(buffer, completionHandler: {
            Task { @MainActor in
                self.playNextAudioChunk()
            }
        })
    }

    private func setupPlaybackEngineIfNeeded() {
        if playbackEngine != nil { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("Audio Playback Engine Error: \(error)")
            return
        }

        playbackEngine = engine
        playbackNode = player
        playbackFormat = format
    }

    private func makePCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard let format = playbackFormat else { return nil }
        let frameCount = UInt32(data.count / 2)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.bindMemory(to: Int16.self).baseAddress,
                  let dst = buffer.int16ChannelData?[0] else {
                return
            }
            dst.update(from: src, count: Int(frameCount))
        }

        return buffer
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
        // During a call, route through WebSocket (may need to queue if connecting)
        if callState.isPresented {
            if connectionState == .connected {
                sendToGemini(text: text, imageData: imageData, message: message)
            } else {
                // Queue for when WebSocket connects
                pendingMessages.append(PendingMessage(message: message, text: text, imageData: imageData))
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
        for item in queued {
            sendToGemini(text: item.text, imageData: item.imageData, message: item.message)
        }
    }

    private func sendToGemini(text: String?, imageData: Data?, message: ChatMessage) {
        // Keep message status as .sending initially (set on buildMessage)
        let result: Result<Void, Error>

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
        }

        if let urlString = message.mediaURL, let url = URL(string: urlString) {
            if message.mediaType == .video {
                geminiService?.sendVideoAttachment(url: url, utType: message.mediaUTType)
            } else if message.mediaType == .document {
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
                mediaURL: attachment?.fileURL?.absoluteString,
                mediaFilename: attachment?.filename,
                mediaUTType: attachment?.utType,
                status: .sending
            )
        case .pdf, .document:
            return ChatMessage(
                role: .user,
                text: text,
                mediaType: .document,
                mediaURL: attachment?.fileURL?.absoluteString,
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

    // New helper to mark latest user message with status .sent if currently .sending
    private func markLatestUserMessageSent() {
        guard let latest = messages.last(where: { $0.role.isUser && $0.status == .sending }) else { return }
        latest.markStatus(.sent)
        print("[Chat] Marked latest user message as Sent")
    }
    
    // New helper to mark latest user message with status .failed if currently .sending
    private func markLatestUserMessageFailedIfSending() {
        guard let latest = messages.last(where: { $0.role.isUser && $0.status == .sending }) else { return }
        latest.markStatus(.failed)
        print("[Chat] Marked latest user message as Failed")
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
        guard !callState.isVideoStreaming else { return }
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
}

// MARK: - Delegate

extension ChatViewModel: GeminiServiceDelegate {
    func geminiServiceDidConnect(_ service: GeminiService) {
        connectionState = .connected
        flushPendingMessages()
        if callState.isPresented {
            startCallTimer()
            sendCallHaptic(style: .success)
            if callKitEnabled {
                callKitManager?.reportConnected()
            }
        }
        if pendingVoiceStart, geminiService?.currentMode == .audio {
            if !callKitEnabled {
                startAudioCapture()
                callState.isListening = true
            }
            pendingVoiceStart = false
        }
    }

    func geminiServiceDidDisconnect(_ service: GeminiService) {
        connectionState = .disconnected
        callState.isListening = false
        isTyping = false
        if callState.isPresented {
            pauseCallTimer()
            pendingVoiceStart = true
            connect(mode: .audio)
        }
    }

    func geminiService(_ service: GeminiService, didReceiveError error: Error) {
        connectionState = .error(error.localizedDescription)
        isTyping = false
        markPendingMessagesFailed()
        markLatestUserMessageFailedIfSending()
        if callState.isPresented {
            pauseCallTimer()
        }
    }

    func geminiService(_ service: GeminiService, didReceiveTranscript transcript: String, isFinal: Bool) {
        // Output transcript: what the AI said (speech-to-text of AI audio)
        // In audio mode, show as assistant message so user can read it
        guard geminiService?.currentMode == .audio else { return }
        let response = ChatMessage(role: .assistant, text: transcript, status: .sent)
        insertMessage(response)
        messages.append(response)
        markLatestUserMessageRead()
    }

    func geminiService(_ service: GeminiService, didReceiveInputTranscript transcript: String, isFinal: Bool) {
        // Input transcript: what the user said (speech-to-text of user audio)
        lastTranscriptText = transcript
        updateDraftMessage(text: transcript, isFinal: isFinal)
        if isFinal {
            cancelTranscriptDebounce()
        } else {
            scheduleTranscriptFinalize()
        }
    }

    func geminiService(_ service: GeminiService, didReceiveResponse text: String) {
        let response = ChatMessage(role: .assistant, text: text, status: .sent)
        insertMessage(response)
        messages.append(response)
        markLatestUserMessageRead()
        geminiService?.notifySendResult(messageID: messages.first(where: { $0.role.isUser })?.id ?? UUID())
    }

    func geminiService(_ service: GeminiService, didReceiveAudio data: Data) {
        finalizeDraftIfNeeded()
        playAudio(data: data)
        markLatestUserMessageRead()
        geminiService?.notifySendResult(messageID: messages.first(where: { $0.role.isUser })?.id ?? UUID())
    }

    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: FunctionResult) {
        geminiService?.notifySendResult(messageID: messages.first(where: { $0.role.isUser })?.id ?? UUID())
    }

    func geminiServiceDidStartResponse(_ service: GeminiService) {
        isTyping = true
        markLatestUserMessageSent()
    }

    func geminiServiceDidEndResponse(_ service: GeminiService) {
        isTyping = false
        markLatestUserMessageRead()
    }
}

