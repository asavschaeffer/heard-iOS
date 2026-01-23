import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers
import UIKit

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

    private struct PendingMessage {
        let message: ChatMessage
        let text: String?
        let imageData: Data?
    }
    
    // MARK: - Initialization

    init() {
        setupAudioSession()
        observeAudioSession()
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
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
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
            self?.updateCallDuration()
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
    }

    var callDurationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = callDuration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: callDuration) ?? "0:00"
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
            self?.handleRouteChange(note)
        })

        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        })
    }

    private func handleRouteChange(_ notification: Notification) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        callState.isListening = audioEngine?.isRunning == true && !outputs.isEmpty
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            stopAudioCapture()
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            if options.contains(.shouldResume) && callState.isPresented {
                startAudioCapture()
                callState.isListening = true
            }
        @unknown default:
            break
        }
    }

    // MARK: - Actions

    func connect() {
        guard connectionState != .connecting else { return }
        connectionState = .connecting
        geminiService?.connect()
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

    // MARK: - Voice Session Management

    func startVoiceSession() {
        let wasPresented = callState.isPresented
        callState.isPresented = true
        if connectionState == .disconnected {
            connect()
        }
        
        if connectionState == .connected {
            preferSpeaker()
            startAudioCapture()
            callState.isListening = true
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
        stopAudioCapture()
        callState.isListening = false
        pendingVoiceStart = false
        stopVideoStreaming()
        cancelTranscriptDebounce()
        finalizeDraftIfNeeded()
        resetCallTimer()
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
        playbackNode?.scheduleBuffer(buffer, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.playNextAudioChunk()
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
            dst.assign(from: src, count: Int(frameCount))
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
        if connectionState == .disconnected {
            connect()
        }

        guard connectionState == .connected else {
            pendingMessages.append(PendingMessage(message: message, text: text, imageData: imageData))
            return
        }

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
        if let text = text, let imageData = imageData, message.mediaType == .image {
            geminiService?.sendTextWithPhoto(text, imageData: imageData)
        } else if let text = text {
            geminiService?.sendText(text)
        } else if let imageData = imageData, message.mediaType == .image {
            geminiService?.sendPhoto(imageData)
        }

        if let urlString = message.mediaURL, let url = URL(string: urlString) {
            if message.mediaType == .video {
                geminiService?.sendVideoAttachment(url: url, utType: message.mediaUTType)
            } else if message.mediaType == .document {
                geminiService?.sendDocumentAttachment(url: url, utType: message.mediaUTType)
            }
        }
        message.markStatus(.sent)
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

        cameraService.setVideoFrameHandler { [weak self] data in
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
        }
        if pendingVoiceStart {
            startAudioCapture()
            callState.isListening = true
            pendingVoiceStart = false
        }
    }

    func geminiServiceDidDisconnect(_ service: GeminiService) {
        connectionState = .disconnected
        callState.isListening = false
        isTyping = false
        if callState.isPresented {
            pauseCallTimer()
        }
        if callState.isPresented {
            pendingVoiceStart = true
        }
    }

    func geminiService(_ service: GeminiService, didReceiveError error: Error) {
        connectionState = .error(error.localizedDescription)
        isTyping = false
        markPendingMessagesFailed()
        if callState.isPresented {
            pauseCallTimer()
        }
    }

    func geminiService(_ service: GeminiService, didReceiveTranscript transcript: String, isFinal: Bool) {
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
    }

    func geminiService(_ service: GeminiService, didReceiveAudio data: Data) {
        finalizeDraftIfNeeded()
        playAudio(data: data)
    }

    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: FunctionResult) {
        // System message? Or just silent?
        // messages.append(.system("Executed \(name)"))
    }

    func geminiServiceDidStartResponse(_ service: GeminiService) {
        isTyping = true
    }

    func geminiServiceDidEndResponse(_ service: GeminiService) {
        isTyping = false
    }
}
