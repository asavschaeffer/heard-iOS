import Foundation
import SwiftUI
import SwiftData
@preconcurrency import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Combine

@MainActor
class ChatViewModel: ObservableObject {

    enum ChatConfig {
        static let transcriptDebounceInterval: TimeInterval = 0.9
        static let captureSampleRate: Double = 16_000
        static let playbackSampleRate: Double = 24_000
        static let audioLevelReportingRate: Double = 25
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
    @Published var callState = CallSessionState()
    @Published var callDuration: TimeInterval = 0
    @Published var callKitEnabled = true
    @Published private(set) var isMicrophoneMuted = false
    @Published private(set) var isSpeakerPreferred = true
    
    // MARK: - Private Properties

    private var geminiService: GeminiService?
    private var modelContext: ModelContext?
    private var audioEngine: AVAudioEngine?
    private var captureConverter: AVAudioConverter?
    private var captureTargetFormat: AVAudioFormat?
    private var playbackEngine: AVAudioEngine?
    private var playbackNode: AVAudioPlayerNode?
    private var playbackInputFormat: AVAudioFormat?
    private var playbackConverter: AVAudioConverter?
    private var playbackFormat: AVAudioFormat?
    private var pendingMessages: [PendingMessage] = []
    private var playbackEnqueuedBufferCount = 0
    private var capturedAudioChunkCount = 0
    private var capturedAudioByteCount = 0
    private var captureTapCallbackCount = 0
    private var consecutiveSilentCaptureStops = 0
    private var useVoiceProcessingInput = true
    private var captureStartedFromCallKit = false
    private var isAdaptingToRouteChange = false
    private var lastRouteAdaptationAt: Date?
    private var draftMessageId: UUID?
    private var assistantTranscriptMessageId: UUID?
    private var assistantTranscriptBuffer: String = ""
    private var assistantTextMessageId: UUID?
    private var assistantTextBuffer: String = ""
    private var inputTranscriptBuffer: String = ""
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
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

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
        reconnectTask?.cancel()
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
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
        } catch {
            print("Audio Session Error: \(error)")
        }
    }

    private func setupCallKit() {
        let manager = CallKitManager(appName: "Heard, Chef")
        manager.onStartAudio = { [weak self] in
            guard let self else { return }
            print("[Audio] CallKit activated audio session")
            self.captureStartedFromCallKit = true
            // Avoid VPIO under CallKit-owned sessions; it can emit repeated render -1 logs
            // while CallKit already provides voice-optimized session behavior.
            self.useVoiceProcessingInput = false
            let session = AVAudioSession.sharedInstance()
            print("[Audio] CallKit session active. sampleRate=\(Int(session.sampleRate))Hz ioBuffer=\(session.ioBufferDuration)s")
            print("[Audio] Voice processing input disabled for CallKit-managed session")
            self.syncSpeakerRouteState()
            if !self.isMicrophoneMuted {
                self.startAudioCapture()
            }
            self.callState.isListening = !self.isMicrophoneMuted
        }
        manager.onStopAudio = { [weak self] in
            print("[Audio] CallKit deactivated audio session")
            self?.stopAudioCapture()
            self?.callState.isListening = false
        }
        manager.onMuteChanged = { [weak self] isMuted in
            guard let self else { return }
            print("[Audio] CallKit mute changed: \(isMuted)")
            self.isMicrophoneMuted = isMuted
            self.callState.isListening = !isMuted
            if !isMuted && self.callState.isPresented && self.audioEngine == nil {
                self.startAudioCapture()
            }
        }
        manager.onTransactionError = { [weak self] error in
            guard let self else { return }
            let details = CallKitManager.describeTransactionError(error)
            let shouldDisableCallKit = CallKitManager.shouldDisableCallKitAfterError(error)
            print("[Audio] CallKit transaction failed (\(details)). fallbackMode=\(shouldDisableCallKit ? "session-disable" : "call-only")")
            self.useVoiceProcessingInput = false
            self.captureStartedFromCallKit = false
            if shouldDisableCallKit {
                self.disableCallKitForSession()
            }
            self.startDirectAudioFallbackPath()
        }
        callKitManager = manager
    }

    private func disableCallKitForSession() {
        guard callKitEnabled else { return }
        callKitEnabled = false
        callKitManager?.onStartAudio = nil
        callKitManager?.onStopAudio = nil
        callKitManager?.onMuteChanged = nil
        callKitManager?.onTransactionError = nil
        callKitManager = nil
    }

    private func startDirectAudioFallbackPath() {
        configureAudioSessionForCall()
        preferSpeaker()
        guard callState.isPresented, !isMicrophoneMuted else { return }
        if connectionState == .connected {
            if audioEngine == nil {
                startAudioCapture()
            }
            callState.isListening = audioEngine?.isRunning == true
            pendingVoiceStart = false
        } else {
            pendingVoiceStart = true
            callState.isListening = false
            print("[Audio] Waiting for Gemini connection before starting fallback capture")
        }
    }

    private func configureAudioSessionForCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            let mode: AVAudioSession.Mode = useVoiceProcessingInput ? .voiceChat : .default
            try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            syncSpeakerRouteState()
            print("[Audio] Session configured. mode=\(mode.rawValue)")
        } catch {
            print("Audio Session Error: \(error)")
        }
    }

    private func syncSpeakerRouteState() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        isSpeakerPreferred = outputs.contains(where: { $0.portType == .builtInSpeaker })
    }

    private func preferSpeaker() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(.speaker)
            isSpeakerPreferred = true
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
        print("[Gemini] Scheduled reconnect in \(String(format: "%.1f", delay))s")
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
        syncSpeakerRouteState()
        callState.isListening = !isMicrophoneMuted && audioEngine?.isRunning == true && !outputs.isEmpty

        guard callState.isPresented else { return }
        let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) ?? .unknown
        let reasonDescription: String
        switch reason {
        case .newDeviceAvailable: reasonDescription = "newDeviceAvailable"
        case .oldDeviceUnavailable: reasonDescription = "oldDeviceUnavailable"
        case .categoryChange: reasonDescription = "categoryChange"
        case .override: reasonDescription = "override"
        case .wakeFromSleep: reasonDescription = "wakeFromSleep"
        case .noSuitableRouteForCategory: reasonDescription = "noSuitableRouteForCategory"
        case .routeConfigurationChange: reasonDescription = "routeConfigurationChange"
        case .unknown: reasonDescription = "unknown"
        @unknown default: reasonDescription = "unhandled(\(reasonValue))"
        }
        print("[Audio] Route change: \(reasonDescription)")

        let shouldAdapt: Bool
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            shouldAdapt = true
        default:
            shouldAdapt = false
        }
        if callKitEnabled {
            // During CallKit-owned sessions, avoid local engine teardown/rebuild on route churn.
            // The system manages the route and rapid restarts can trigger VPIO render errors.
            return
        }
        guard shouldAdapt else { return }
        adaptToDeviceChange()
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
                if !callKitEnabled && !isMicrophoneMuted {
                    startAudioCapture()
                }
                callState.isListening = !isMicrophoneMuted
            }
        @unknown default:
            break
        }
    }

    // MARK: - Actions

    /// Connect Gemini Live WebSocket with the requested session mode.
    func connect(mode: SessionMode = .audio) {
        guard connectionState != .connecting else { return }
        connectionState = .connecting
        let config: SessionConfig = {
            switch mode {
            case .audio:
                return .audio()
            case .text:
                return .text()
            }
        }()
        geminiService?.connect(config: config)
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
        print("[UI] Voice session start requested")
        let wasPresented = callState.isPresented
        if wasPresented { return }
        captureStartedFromCallKit = false
        callState.isPresented = true
        isMicrophoneMuted = false
        callState.isListening = true
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
                if !isMicrophoneMuted {
                    startAudioCapture()
                }
                callState.isListening = !isMicrophoneMuted
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
        print("[UI] Voice session stop requested")
        let wasPresented = callState.isPresented
        callState.isPresented = false
        captureStartedFromCallKit = false
        // TODO: End Live Activity when Dynamic Island is implemented.
        liveActivityManager.endCallActivity()
        if callKitEnabled {
            callKitManager?.endCall()
        } else {
            stopAudioCapture()
            callState.isListening = false
        }
        stopPlayback()
        isMicrophoneMuted = false
        pendingVoiceStart = false
        resetReconnectBackoff()
        stopVideoStreaming()
        cancelTranscriptDebounce()
        finalizeDraftIfNeeded()
        finalizeAssistantStreamingMessages()
        inputTranscriptBuffer = ""
        resetCallTimer()
        // Disconnect the audio session; next text send will lazy-reconnect in text mode
        geminiService?.disconnect()
        connectionState = .disconnected
        if wasPresented {
            sendCallHaptic(style: .warning)
        }
    }
    
    func toggleMute() {
        isMicrophoneMuted.toggle()
        print("[UI] Microphone \(isMicrophoneMuted ? "muted" : "unmuted")")
        callState.isListening = !isMicrophoneMuted
        if !isMicrophoneMuted && callState.isPresented && audioEngine == nil {
            startAudioCapture()
        }
    }

    func toggleSpeaker() {
        let session = AVAudioSession.sharedInstance()
        do {
            let shouldPreferSpeaker = !isSpeakerPreferred
            try session.overrideOutputAudioPort(shouldPreferSpeaker ? .speaker : .none)
            isSpeakerPreferred = shouldPreferSpeaker
            print("[UI] Speaker preference set to \(shouldPreferSpeaker ? "speaker" : "system route")")
        } catch {
            print("Audio Session override error: \(error)")
        }
    }

    // MARK: - Audio Engine

    private func startAudioCapture() {
        // Prevent double start
        if audioEngine?.isRunning == true { return }
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if useVoiceProcessingInput {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                print("[Audio] Voice processing input enabled")
            } catch {
                print("[Audio] Voice processing enable failed, using fallback input path: \(error)")
                useVoiceProcessingInput = false
            }
        } else {
            print("[Audio] Voice processing input disabled (fallback mode)")
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("[Audio] Starting capture. inputRate=\(Int(inputFormat.sampleRate))Hz channels=\(inputFormat.channelCount)")
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: ChatConfig.captureSampleRate,
            channels: 1,
            interleaved: false
        ),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("Audio conversion setup error")
            return
        }

        captureConverter = converter
        captureTargetFormat = targetFormat
        audioEngine = engine

        let bufferSize = AVAudioFrameCount(max(256.0, inputFormat.sampleRate / ChatConfig.audioLevelReportingRate))
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            captureTapCallbackCount = 0
            capturedAudioChunkCount = 0
            capturedAudioByteCount = 0
            print("[Audio] Capture started. targetRate=\(Int(ChatConfig.captureSampleRate))Hz")
        } catch {
            print("Audio Engine Start Error: \(error)")
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
            captureConverter = nil
            captureTargetFormat = nil
        }
    }

    private func stopAudioCapture() {
        if capturedAudioChunkCount > 0 {
            consecutiveSilentCaptureStops = 0
            print("[Audio] Capture stopped. callbacks=\(captureTapCallbackCount) chunks=\(capturedAudioChunkCount) bytes=\(capturedAudioByteCount)")
        } else {
            consecutiveSilentCaptureStops += 1
            print("[Audio] Capture stopped with no outgoing chunks (callbacks=\(captureTapCallbackCount))")
            if callState.isPresented && useVoiceProcessingInput && consecutiveSilentCaptureStops >= 3 {
                print("[Audio] Switching to non-voice-processing input after repeated zero-chunk stops")
                useVoiceProcessingInput = false
            }
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        captureConverter = nil
        captureTargetFormat = nil
        callState.audioLevel = 0
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        captureTapCallbackCount += 1
        if captureTapCallbackCount == 1 || captureTapCallbackCount % 50 == 0 {
            print("[Audio] Tap callback #\(captureTapCallbackCount), frames=\(buffer.frameLength)")
        }

        if useVoiceProcessingInput,
           callState.isPresented,
           connectionState == .connected,
           !isMicrophoneMuted,
           captureTapCallbackCount >= 150,
           capturedAudioChunkCount == 0 {
            print("[Audio] No outgoing chunks while callbacks are firing on voice-processing path; switching to fallback input")
            useVoiceProcessingInput = false
            stopAudioCapture()
            startAudioCapture()
            return
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        if let channelData = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameLength { sum += abs(channelData[i]) }
            let average = sum / Float(frameLength)

            Task { @MainActor in
                self.callState.audioLevel = min(1.0, average * 10)
            }
        }

        guard !isMicrophoneMuted else { return }
        guard connectionState == .connected else { return }
        guard let pcmData = convertCapturedBufferToPCM16(buffer), !pcmData.isEmpty else {
            return
        }

        capturedAudioChunkCount += 1
        capturedAudioByteCount += pcmData.count
        if capturedAudioChunkCount == 1 || capturedAudioChunkCount % 200 == 0 {
            print("[Audio] Captured chunk #\(capturedAudioChunkCount), bytes=\(pcmData.count), totalBytes=\(capturedAudioByteCount)")
        }

        geminiService?.sendAudio(data: pcmData)
    }

    private func convertCapturedBufferToPCM16(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = captureConverter, let targetFormat = captureTargetFormat else { return nil }

        let sampleRateRatio = targetFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let outputFrameCapacity = AVAudioFrameCount(max(1, ceil(Double(buffer.frameLength) * sampleRateRatio)))

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }

        var error: NSError?
        var inputConsumed = false
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }

            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            if let error {
                print("Audio conversion error: \(error)")
            }
            return nil
        }

        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0,
              let channelData = convertedBuffer.int16ChannelData?[0] else {
            return nil
        }

        let byteCount = frameLength * MemoryLayout<Int16>.size
        return Data(bytes: channelData, count: byteCount)
    }

    // MARK: - Audio Playback

    private func playAudio(data: Data) {
        guard !data.isEmpty else { return }
        setupPlaybackEngineIfNeeded()
        guard let buffer = makePCMBuffer(from: data) else { return }

        if let engine = playbackEngine, !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Audio Playback restart error: \(error)")
                return
            }
        }

        if playbackNode?.isPlaying == false {
            playbackNode?.play()
        }

        incrementPlaybackBufferCount()
        playbackNode?.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack, completionHandler: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.decrementPlaybackBufferCount()
            }
        })
    }

    private func setupPlaybackEngineIfNeeded() {
        if playbackEngine != nil { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: ChatConfig.playbackSampleRate,
            channels: 1,
            interleaved: false
        ),
              let outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Audio Playback format setup error")
            return
        }

        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

        do {
            try engine.start()
        } catch {
            print("Audio Playback Engine Error: \(error)")
            return
        }

        playbackEngine = engine
        playbackNode = player
        playbackInputFormat = inputFormat
        playbackConverter = converter
        playbackFormat = outputFormat
    }

    private func makePCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard let inputFormat = playbackInputFormat,
              let outputFormat = playbackFormat,
              let converter = playbackConverter else { return nil }

        let bytesPerFrame = Int(inputFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }

        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return nil
        }

        inputBuffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.bindMemory(to: Int16.self).baseAddress,
                  let dst = inputBuffer.int16ChannelData?[0] else {
                return
            }
            dst.update(from: src, count: Int(frameCount))
        }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return nil
        }

        do {
            try converter.convert(to: outputBuffer, from: inputBuffer)
            return outputBuffer.frameLength > 0 ? outputBuffer : nil
        } catch {
            print("Audio Playback conversion error: \(error)")
            return nil
        }
    }

    private func stopPlayback(clearQueue: Bool = true) {
        _ = clearQueue
        playbackEnqueuedBufferCount = 0
        callState.isSpeaking = false
        playbackNode?.stop()
        playbackEngine?.stop()
        playbackNode = nil
        playbackEngine = nil
        playbackInputFormat = nil
        playbackConverter = nil
        playbackFormat = nil
    }

    private func adaptToDeviceChange() {
        if isAdaptingToRouteChange {
            return
        }
        if let last = lastRouteAdaptationAt,
           Date().timeIntervalSince(last) < 1.0 {
            return
        }
        isAdaptingToRouteChange = true
        defer {
            isAdaptingToRouteChange = false
            lastRouteAdaptationAt = Date()
        }

        let shouldResumeCapture = callState.isPresented &&
            connectionState == .connected &&
            !isMicrophoneMuted &&
            audioEngine != nil
        let shouldResumePlayback = playbackEngine != nil || playbackEnqueuedBufferCount > 0 || playbackNode?.isPlaying == true

        guard shouldResumeCapture || shouldResumePlayback else { return }

        stopAudioCapture()
        stopPlayback(clearQueue: false)

        if shouldResumeCapture {
            startAudioCapture()
            callState.isListening = !isMicrophoneMuted && audioEngine?.isRunning == true
        }

        if shouldResumePlayback {
            setupPlaybackEngineIfNeeded()
        }
    }

    private func incrementPlaybackBufferCount() {
        playbackEnqueuedBufferCount += 1
        if playbackEnqueuedBufferCount == 1 {
            callState.isSpeaking = true
        }
    }

    private func decrementPlaybackBufferCount() {
        playbackEnqueuedBufferCount = max(0, playbackEnqueuedBufferCount - 1)
        if playbackEnqueuedBufferCount == 0 {
            callState.isSpeaking = false
        }
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

    private func updateAssistantTranscriptMessage(chunk: String, isFinal: Bool) {
        guard !chunk.isEmpty else { return }

        assistantTranscriptBuffer = mergeStreamingText(existing: assistantTranscriptBuffer, incoming: chunk)
        let text = assistantTranscriptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let messageId = assistantTranscriptMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].updateText(text, isDraft: !isFinal)
            attachUnanchoredToolChips(to: messageId)
        } else {
            let message = ChatMessage(role: .assistant, text: text, status: .sent, isDraft: !isFinal)
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
        let text = assistantTextBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let messageId = assistantTextMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].updateText(text, isDraft: !isFinal)
            attachUnanchoredToolChips(to: messageId)
        } else {
            let message = ChatMessage(role: .assistant, text: text, status: .sent, isDraft: !isFinal)
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
            let finalText = assistantTranscriptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalText.isEmpty {
                let message = messages.remove(at: index)
                modelContext?.delete(message)
            } else {
                messages[index].updateText(finalText, isDraft: false)
            }
        }
        assistantTranscriptMessageId = nil
        assistantTranscriptBuffer = ""

        if let messageId = assistantTextMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            let finalText = assistantTextBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalText.isEmpty {
                let message = messages.remove(at: index)
                modelContext?.delete(message)
            } else {
                messages[index].updateText(finalText, isDraft: false)
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
}

// MARK: - Delegate

extension ChatViewModel: GeminiServiceDelegate {
    func geminiServiceDidConnect(_ service: GeminiService) {
        connectionState = .connected
        resetReconnectBackoff()
        print("[Gemini] Connected. callKitEnabled=\(callKitEnabled) pendingVoiceStart=\(pendingVoiceStart)")
        flushPendingMessages()
        if callState.isPresented {
            startCallTimer()
            sendCallHaptic(style: .success)
            if callKitEnabled {
                callKitManager?.reportConnected()
            }
        }
        if pendingVoiceStart, geminiService?.currentMode == .audio {
            if (!callKitEnabled || !captureStartedFromCallKit) && !isMicrophoneMuted {
                startAudioCapture()
            }
            callState.isListening = !isMicrophoneMuted
            pendingVoiceStart = false
        }
    }

    func geminiServiceDidDisconnect(_ service: GeminiService) {
        let shouldAutoReconnect: Bool = {
            if case .error = connectionState { return false }
            return true
        }()
        finalizeAssistantStreamingMessages()
        connectionState = .disconnected
        callState.isListening = false
        isTyping = false
        if callState.isPresented {
            pauseCallTimer()
            pendingVoiceStart = true
            if shouldAutoReconnect {
                scheduleAudioReconnect()
            }
        }
    }

    func geminiService(_ service: GeminiService, didReceiveError error: Error) {
        connectionState = .error(error.localizedDescription)
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
            print("[Gemini] Output transcript final: \(transcript)")
        }
        // Output transcript: what the AI said (speech-to-text of AI audio)
        // In audio mode, show as assistant message so user can read it
        guard geminiService?.currentMode == .audio else { return }
        updateAssistantTranscriptMessage(chunk: transcript, isFinal: isFinal)
        markLatestUserMessageRead()
    }

    func geminiService(_ service: GeminiService, didReceiveInputTranscript transcript: String, isFinal: Bool) {
        if isFinal {
            print("[Gemini] Input transcript final: \(transcript)")
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
        print("[Gemini] Response text received chars=\(text.count) preview=\(preview)")
        updateAssistantTextMessage(chunk: text, isFinal: false)
        markLatestUserMessageRead()
        service.notifyCurrentSendResult()
    }

    func geminiService(_ service: GeminiService, didReceiveAudio data: Data) {
        print("[Gemini] Response audio received bytes=\(data.count)")
        finalizeDraftIfNeeded()
        playAudio(data: data)
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
