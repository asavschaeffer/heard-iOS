import Foundation
import SwiftUI
import SwiftData
import AVFoundation

@MainActor
class VoiceViewModel: ObservableObject {

    enum VoiceConfig {
        static let transcriptDebounceInterval: TimeInterval = 0.9
    }

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Message Model
    
    struct ChatMessage: Identifiable, Equatable {
        let id: UUID
        let isUser: Bool
        let text: String?
        let imageData: Data?
        let timestamp: Date
        let isDraft: Bool
        
        static func userText(_ text: String) -> ChatMessage {
            make(isUser: true, text: text, imageData: nil, isDraft: false)
        }
        
        static func userImage(_ data: Data) -> ChatMessage {
            make(isUser: true, text: nil, imageData: data, isDraft: false)
        }

        static func userTextWithImage(_ text: String, imageData: Data?) -> ChatMessage {
            make(isUser: true, text: text, imageData: imageData, isDraft: false)
        }
        
        static func aiText(_ text: String) -> ChatMessage {
            make(isUser: false, text: text, imageData: nil, isDraft: false)
        }

        static func draftUserText(_ text: String) -> ChatMessage {
            make(isUser: true, text: text, imageData: nil, isDraft: true)
        }

        static func draftUserText(_ text: String, id: UUID) -> ChatMessage {
            make(isUser: true, text: text, imageData: nil, isDraft: true, id: id)
        }

        static func userText(_ text: String, id: UUID) -> ChatMessage {
            make(isUser: true, text: text, imageData: nil, isDraft: false, id: id)
        }

        private static func make(
            isUser: Bool,
            text: String?,
            imageData: Data?,
            isDraft: Bool,
            id: UUID = UUID()
        ) -> ChatMessage {
            ChatMessage(id: id, isUser: isUser, text: text, imageData: imageData, timestamp: Date(), isDraft: isDraft)
        }
    }

    // MARK: - Published Properties

    @Published var connectionState: ConnectionState = .disconnected
    @Published var messages: [ChatMessage] = []
    
    // Voice Mode State
    @Published var showVoiceMode = false
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var audioLevel: Float = 0.0
    
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

    private struct PendingMessage {
        let text: String?
        let imageData: Data?
    }
    
    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.geminiService = GeminiService(modelContext: context)
        self.geminiService?.delegate = self
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
        sendMessage(text, imageData: nil)
    }

    func sendMessage(_ text: String, imageData: Data?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty

        if hasText && imageData != nil {
            messages.append(.userTextWithImage(trimmed, imageData: imageData))
        } else if hasText {
            messages.append(.userText(trimmed))
        } else if let imageData = imageData {
            messages.append(.userImage(imageData))
        } else {
            return
        }

        enqueueOrSend(text: hasText ? trimmed : nil, imageData: imageData)
    }

    func sendImage(_ data: Data) {
        messages.append(.userImage(data))
        enqueueOrSend(text: nil, imageData: data)
    }

    // MARK: - Voice Session Management

    func startVoiceSession() {
        showVoiceMode = true
        if connectionState == .disconnected {
            connect()
        }
        
        if connectionState == .connected {
            startAudioCapture()
            isListening = true
            pendingVoiceStart = false
        } else {
            pendingVoiceStart = true
        }
    }

    func stopVoiceSession() {
        showVoiceMode = false
        stopAudioCapture()
        isListening = false
        pendingVoiceStart = false
        cancelTranscriptDebounce()
        finalizeDraftIfNeeded()
    }
    
    func toggleMute() {
        isListening.toggle()
        if isListening {
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
        audioLevel = 0
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. Visuals
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength { sum += abs(channelData[i]) }
        let average = sum / Float(frameLength)
        
        Task { @MainActor in
            self.audioLevel = min(1.0, average * 10)
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
            isSpeaking = false
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

        isSpeaking = true
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

    private func enqueueOrSend(text: String?, imageData: Data?) {
        if connectionState == .disconnected {
            connect()
        }

        guard connectionState == .connected else {
            pendingMessages.append(PendingMessage(text: text, imageData: imageData))
            return
        }

        sendToGemini(text: text, imageData: imageData)
    }

    private func flushPendingMessages() {
        guard connectionState == .connected else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        for item in queued {
            sendToGemini(text: item.text, imageData: item.imageData)
        }
    }

    private func sendToGemini(text: String?, imageData: Data?) {
        if let text = text, let imageData = imageData {
            geminiService?.sendTextWithPhoto(text, imageData: imageData)
        } else if let text = text {
            geminiService?.sendText(text)
        } else if let imageData = imageData {
            geminiService?.sendPhoto(imageData)
        }
    }

    // MARK: - Transcript Handling

    private func updateDraftMessage(text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal && trimmed.isEmpty {
            clearDraftMessage()
            return
        }

        if let draftId = draftMessageId, let index = messages.firstIndex(where: { $0.id == draftId }) {
            let updated = isFinal
                ? ChatMessage.userText(trimmed.isEmpty ? text : trimmed, id: draftId)
                : ChatMessage.draftUserText(text, id: draftId)
            messages[index] = updated
        } else {
            let newDraft = isFinal
                ? ChatMessage.userText(trimmed.isEmpty ? text : trimmed)
                : ChatMessage.draftUserText(text)
            messages.append(newDraft)
            draftMessageId = newDraft.id
        }

        if isFinal {
            draftMessageId = nil
        }
    }

    private func clearDraftMessage() {
        if let draftId = draftMessageId, let index = messages.firstIndex(where: { $0.id == draftId }) {
            messages.remove(at: index)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + VoiceConfig.transcriptDebounceInterval, execute: workItem)
    }

    private func cancelTranscriptDebounce() {
        transcriptDebounceWorkItem?.cancel()
        transcriptDebounceWorkItem = nil
    }
}

// MARK: - Delegate

extension VoiceViewModel: GeminiServiceDelegate {
    func geminiServiceDidConnect(_ service: GeminiService) {
        connectionState = .connected
        flushPendingMessages()
        if pendingVoiceStart {
            startAudioCapture()
            isListening = true
            pendingVoiceStart = false
        }
    }

    func geminiServiceDidDisconnect(_ service: GeminiService) {
        connectionState = .disconnected
        isListening = false
        if showVoiceMode {
            pendingVoiceStart = true
        }
    }

    func geminiService(_ service: GeminiService, didReceiveError error: Error) {
        connectionState = .error(error.localizedDescription)
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
        messages.append(.aiText(text))
    }

    func geminiService(_ service: GeminiService, didReceiveAudio data: Data) {
        finalizeDraftIfNeeded()
        playAudio(data: data)
    }

    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: FunctionResult) {
        // System message? Or just silent?
        // messages.append(.system("Executed \(name)"))
    }
}
