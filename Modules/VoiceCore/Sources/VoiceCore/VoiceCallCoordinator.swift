import Foundation
@preconcurrency import AVFoundation

@MainActor
protocol VoiceCallKitControlling: AnyObject {
    var onStartAudio: (() -> Void)? { get set }
    var onStopAudio: (() -> Void)? { get set }
    var onMuteChanged: ((Bool) -> Void)? { get set }
    var onTransactionError: ((Error) -> Void)? { get set }

    func startCall(displayName: String)
    func endCall()
    func reportConnected()
}

extension CallKitManager: VoiceCallKitControlling {}

@MainActor
public protocol VoiceCallCoordinatorDelegate: AnyObject {
    func voiceCallCoordinator(_ coordinator: VoiceCallCoordinator, didUpdate state: VoiceCallUIState)
    func voiceCallCoordinator(_ coordinator: VoiceCallCoordinator, didChangeCallKitEnabled isEnabled: Bool)
}

@MainActor
public final class VoiceCallCoordinator {
    public weak var delegate: VoiceCallCoordinatorDelegate?
    public var onCapturedAudio: ((Data) -> Void)?

    private let displayName: String
    private let audioSessionController: VoiceAudioSessionControlling
    private let captureEngine: VoiceCaptureHandling
    private let playbackEngine: VoicePlaybackHandling
    private let describeTransactionError: (Error) -> String
    private let shouldDisableCallKitAfterError: (Error) -> Bool
    private var callKitManager: VoiceCallKitControlling?
    private var audioObservers: [NSObjectProtocol] = []
    private var transportState: VoiceTransportState = .disconnected
    private var isAdaptingToRouteChange = false
    private var lastRouteAdaptationAt: Date?

    public private(set) var state = VoiceCallUIState()
    public private(set) var callKitEnabled: Bool

    public convenience init(displayName: String, callKitEnabled: Bool = true) {
        self.init(
            displayName: displayName,
            callKitEnabled: callKitEnabled,
            callKitManager: callKitEnabled ? CallKitManager(appName: displayName) : nil,
            audioSessionController: VoiceAudioSessionController(),
            captureEngine: VoiceCaptureEngine(),
            playbackEngine: VoicePlaybackEngine()
        )
    }

    init(
        displayName: String,
        callKitEnabled: Bool,
        callKitManager: VoiceCallKitControlling?,
        audioSessionController: VoiceAudioSessionControlling,
        captureEngine: VoiceCaptureHandling,
        playbackEngine: VoicePlaybackHandling,
        describeTransactionError: @escaping (Error) -> String = CallKitManager.describeTransactionError,
        shouldDisableCallKitAfterError: @escaping (Error) -> Bool = CallKitManager.shouldDisableCallKitAfterError
    ) {
        self.displayName = displayName
        self.callKitEnabled = callKitEnabled
        self.callKitManager = callKitManager
        self.audioSessionController = audioSessionController
        self.captureEngine = captureEngine
        self.playbackEngine = playbackEngine
        self.describeTransactionError = describeTransactionError
        self.shouldDisableCallKitAfterError = shouldDisableCallKitAfterError

        if !callKitEnabled {
            audioSessionController.configureNonCallKitSession(preferSpeaker: state.isSpeakerPreferred)
            syncSpeakerPreferenceFromSession()
        }

        wireCallbacks()
        observeAudioSession()
        publishState()
    }

    deinit {
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func updateTransportState(_ state: VoiceTransportState) {
        transportState = state
    }

    public func transportWillConnect() {
        transportState = .connecting
    }

    public func transportDidFail(message: String) {
        transportState = .error(message)
    }

    public func startCall() {
        logAudioState("Voice session start requested")
        let wasPresented = state.isPresented
        if wasPresented { return }

        state.isPresented = true
        state.isMicrophoneMuted = false
        state.isListening = true
        state.pendingVoiceStart = transportState != .connected
        state.captureStartedFromCallKit = false
        state.audioLevel = 0
        publishState()

        if callKitEnabled {
            callKitManager?.startCall(displayName: displayName)
        } else {
            startDirectAudioFallbackPath()
        }

        if transportState == .connected {
            state.pendingVoiceStart = false
        }

        publishState()
        logAudioState("Voice session start finished")
    }

    public func stopCall() {
        logAudioState("Voice session stop requested")
        state.isPresented = false
        state.isListening = false
        state.isMicrophoneMuted = false
        state.pendingVoiceStart = false
        state.captureStartedFromCallKit = false
        state.audioLevel = 0
        publishState()

        if callKitEnabled {
            callKitManager?.endCall()
        } else {
            stopCapture()
        }
        stopPlayback()
        publishState()
        logAudioState("Voice session stop finished")
    }

    public func toggleMute() {
        state.isMicrophoneMuted.toggle()
        updateListeningState()
        publishState()
        logAudioState("Microphone toggle", extra: "isMuted=\(state.isMicrophoneMuted)")

        if !state.isMicrophoneMuted && state.isPresented && !captureEngine.isRunning && shouldStartCaptureNow {
            startCapture()
        }
    }

    public func toggleSpeaker() {
        let shouldPreferSpeaker = !state.isSpeakerPreferred
        logAudioState(
            "Speaker toggle requested",
            extra: "target=\(shouldPreferSpeaker ? "speaker" : "receiver/system")"
        )

        if callKitEnabled && state.captureStartedFromCallKit {
            audioSessionController.configureActiveCallKitSession(preferSpeaker: shouldPreferSpeaker)
        } else {
            do {
                try audioSessionController.applyOutputOverride(preferSpeaker: shouldPreferSpeaker)
            } catch {
                VoiceDiagnostics.fault("[Audio] Speaker toggle failed error=\(error.localizedDescription)")
            }
        }

        syncSpeakerPreferenceFromSession()
        publishState()
        logAudioState(
            "Speaker toggle applied",
            extra: "target=\(shouldPreferSpeaker ? "speaker" : "receiver/system")"
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.logAudioState(
                "Speaker toggle settled",
                extra: "target=\(shouldPreferSpeaker ? "speaker" : "receiver/system")"
            )
        }
    }

    public func transportDidConnect() {
        transportState = .connected
        logAudioState("Gemini delegate connected")

        if state.isPresented {
            if callKitEnabled {
                callKitManager?.reportConnected()
            }

            if state.pendingVoiceStart {
                if !callKitEnabled && !state.isMicrophoneMuted {
                    startCapture()
                }
                state.isListening = !state.isMicrophoneMuted
                state.pendingVoiceStart = false
                publishState()
            }
        }
    }

    public func transportDidDisconnect() {
        transportState = .disconnected
        state.isListening = false
        if state.isPresented {
            state.pendingVoiceStart = true
        }
        publishState()
        logAudioState("Gemini delegate disconnected", extra: "autoReconnect=true")
    }

    public func transportDidReceiveAudio(_ data: Data) {
        playbackEngine.play(data)
        state.isPlaybackRunning = playbackEngine.isRunning
        publishState()
    }

    func handleRouteChangeNotification(_ notification: Notification) {
        let event = audioSessionController.routeChangeEvent(from: notification)
        handleRouteChange(event)
    }

    func handleInterruptionNotification(_ notification: Notification) {
        guard let event = audioSessionController.interruptionEvent(from: notification) else { return }
        handleInterruption(event)
    }

    func handleRouteChange(_ event: VoiceRouteChangeEvent) {
        syncSpeakerPreferenceFromSession()
        updateListeningState()
        publishState()

        guard state.isPresented else { return }

        logAudioState(
            "Route change observed",
            extra: "reason=\(event.reasonDescription) previousRoute=\(event.previousRouteDescription)"
        )

        if callKitEnabled {
            if event.shouldAdapt && !state.useVoiceProcessingInput {
                logAudioState(
                    "CallKit route change will reconfigure local audio graphs",
                    extra: "reason=\(event.reasonDescription)"
                )
                adaptToDeviceChange()
                return
            }

            if event.shouldAdapt || event.reason == .override {
                playbackEngine.resetIdleGraphForRouteChange(reason: event.reasonDescription)
                state.isPlaybackRunning = playbackEngine.isRunning
            }
            publishState()
            logAudioState("Route change ignored because CallKit owns session", extra: "reason=\(event.reasonDescription)")
            return
        }

        guard event.shouldAdapt else { return }
        adaptToDeviceChange()
    }

    func handleInterruption(_ event: VoiceInterruptionEvent) {
        switch event.type {
        case .began:
            logAudioState("Audio interruption", extra: "type=\(event.typeDescription)")
            if !callKitEnabled {
                stopCapture()
            }
        case .ended:
            logAudioState(
                "Audio interruption",
                extra: "type=\(event.typeDescription) options=\(event.optionsDescription)"
            )
            if event.shouldResume && state.isPresented {
                if !callKitEnabled && !state.isMicrophoneMuted {
                    startCapture()
                }
                state.isListening = !state.isMicrophoneMuted
                publishState()
            }
        @unknown default:
            break
        }
    }

    private var shouldStartCaptureNow: Bool {
        state.isPresented && transportState == .connected && !state.isMicrophoneMuted
    }

    private func wireCallbacks() {
        captureEngine.shouldSendAudio = { [weak self] in
            guard let self else { return false }
            return self.state.isPresented && self.transportState == .connected && !self.state.isMicrophoneMuted
        }
        captureEngine.onAudioLevel = { [weak self] level in
            self?.state.audioLevel = level
            self?.publishState()
        }
        captureEngine.onAudioData = { [weak self] data in
            self?.onCapturedAudio?(data)
        }
        captureEngine.onVoiceProcessingFallbackRequested = { [weak self] in
            self?.restartCaptureForVoiceProcessingFallback()
        }

        playbackEngine.onSpeakingChanged = { [weak self] isSpeaking in
            self?.state.isSpeaking = isSpeaking
            self?.publishState()
        }
        playbackEngine.onRunningChanged = { [weak self] isRunning in
            self?.state.isPlaybackRunning = isRunning
            self?.publishState()
        }

        callKitManager?.onStartAudio = { [weak self] in
            self?.handleCallKitDidActivate()
        }
        callKitManager?.onStopAudio = { [weak self] in
            self?.handleCallKitDidDeactivate()
        }
        callKitManager?.onMuteChanged = { [weak self] isMuted in
            self?.handleCallKitMuteChanged(isMuted: isMuted)
        }
        callKitManager?.onTransactionError = { [weak self] error in
            self?.handleCallKitTransactionError(error)
        }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleRouteChangeNotification(notification)
            }
        })

        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleInterruptionNotification(notification)
            }
        })
    }

    private func handleCallKitDidActivate() {
        state.captureStartedFromCallKit = true
        captureEngine.useVoiceProcessingInput = false
        state.useVoiceProcessingInput = false
        audioSessionController.configureActiveCallKitSession(preferSpeaker: nil)
        syncSpeakerPreferenceFromSession()
        publishState()
        logAudioState("CallKit session configured", extra: "mode=voiceChat speakerOverride=preserve")
        logAudioState("CallKit activated audio session")

        if !state.isMicrophoneMuted {
            startCapture()
        }
        state.isListening = !state.isMicrophoneMuted
        publishState()
    }

    private func handleCallKitDidDeactivate() {
        logAudioState("CallKit deactivated audio session", extra: "phase=before-stop")
        stopCapture()
        state.isListening = false
        publishState()
        logAudioState("CallKit deactivated audio session", extra: "phase=after-stop")
    }

    private func handleCallKitMuteChanged(isMuted: Bool) {
        state.isMicrophoneMuted = isMuted
        updateListeningState()
        publishState()
        logAudioState("CallKit mute changed", extra: "isMuted=\(isMuted)")
        if !isMuted && state.isPresented && !captureEngine.isRunning && shouldStartCaptureNow {
            startCapture()
        }
    }

    private func handleCallKitTransactionError(_ error: Error) {
        let details = describeTransactionError(error)
        let disableCallKit = shouldDisableCallKitAfterError(error)
        logAudioState(
            "CallKit transaction failed",
            extra: "details=\(details) fallbackMode=\(disableCallKit ? "session-disable" : "call-only")"
        )

        captureEngine.useVoiceProcessingInput = false
        state.useVoiceProcessingInput = false
        state.captureStartedFromCallKit = false
        publishState()

        if disableCallKit {
            disableCallKitForSession()
        }
        startDirectAudioFallbackPath()
    }

    private func disableCallKitForSession() {
        guard callKitEnabled else { return }
        callKitEnabled = false
        callKitManager?.onStartAudio = nil
        callKitManager?.onStopAudio = nil
        callKitManager?.onMuteChanged = nil
        callKitManager?.onTransactionError = nil
        callKitManager = nil
        delegate?.voiceCallCoordinator(self, didChangeCallKitEnabled: false)
        logAudioState("CallKit disabled for current session")
    }

    private func startDirectAudioFallbackPath() {
        audioSessionController.configureNonCallKitSession(preferSpeaker: state.isSpeakerPreferred)
        syncSpeakerPreferenceFromSession()
        if state.isPresented && !state.isMicrophoneMuted {
            if transportState == .connected {
                if !captureEngine.isRunning {
                    startCapture()
                }
                state.isListening = captureEngine.isRunning
                state.pendingVoiceStart = false
            } else {
                state.pendingVoiceStart = true
                state.isListening = false
                VoiceDiagnostics.audio("[Audio] Waiting for Gemini connection before starting fallback capture")
            }
        }
        publishState()
        logAudioState("Started direct audio fallback path")
    }

    private func restartCaptureForVoiceProcessingFallback() {
        guard state.isPresented else { return }
        stopCapture()
        if shouldStartCaptureNow {
            startCapture()
        }
    }

    private func startCapture() {
        captureEngine.start()
        state.useVoiceProcessingInput = captureEngine.useVoiceProcessingInput
        state.isCaptureRunning = captureEngine.isRunning
        updateListeningState()
        publishState()
    }

    private func stopCapture() {
        let hadEngine = captureEngine.isRunning
        let metrics = captureEngine.stop()
        state.useVoiceProcessingInput = captureEngine.useVoiceProcessingInput
        state.isCaptureRunning = captureEngine.isRunning
        state.audioLevel = 0
        updateListeningState()
        publishState()
        logAudioState(
            hadEngine ? "Capture stopped" : "Capture stop requested with no active engine",
            extra: "callbacks=\(metrics.callbackCount) chunks=\(metrics.chunkCount) bytes=\(metrics.byteCount)"
        )
    }

    private func stopPlayback() {
        playbackEngine.stop(clearQueue: true)
        state.isPlaybackRunning = playbackEngine.isRunning
        state.isSpeaking = playbackEngine.isSpeaking
        publishState()
    }

    private func adaptToDeviceChange() {
        if isAdaptingToRouteChange {
            logAudioState("Route adaptation skipped", extra: "reason=already-adapting")
            return
        }

        if let lastRouteAdaptationAt,
           Date().timeIntervalSince(lastRouteAdaptationAt) < 1.0 {
            logAudioState("Route adaptation skipped", extra: "reason=debounced")
            return
        }

        isAdaptingToRouteChange = true
        defer {
            isAdaptingToRouteChange = false
            lastRouteAdaptationAt = Date()
        }

        let shouldResumeCapture = state.isPresented &&
            transportState == .connected &&
            !state.isMicrophoneMuted &&
            captureEngine.isRunning
        let shouldResumePlayback = playbackEngine.isRunning || playbackEngine.enqueuedBufferCount > 0 || playbackEngine.isSpeaking
        guard shouldResumeCapture || shouldResumePlayback else { return }

        logAudioState(
            "Route adaptation started",
            extra: "resumeCapture=\(shouldResumeCapture) resumePlayback=\(shouldResumePlayback)"
        )

        _ = captureEngine.stop()
        state.isCaptureRunning = captureEngine.isRunning
        playbackEngine.stop(clearQueue: false)
        state.isPlaybackRunning = playbackEngine.isRunning
        state.isSpeaking = false
        publishState()

        if shouldResumeCapture {
            startCapture()
        }

        if shouldResumePlayback {
            playbackEngine.prepareIfNeeded()
            state.isPlaybackRunning = playbackEngine.isRunning
            publishState()
        }

        logAudioState("Route adaptation finished")
    }

    private func updateListeningState() {
        if !state.isPresented {
            state.isListening = false
            return
        }

        if state.isMicrophoneMuted {
            state.isListening = false
            return
        }

        if state.pendingVoiceStart {
            state.isListening = false
            return
        }

        state.isListening = captureEngine.isRunning && audioSessionController.currentRouteHasOutputs()
    }

    private func syncSpeakerPreferenceFromSession() {
        state.isSpeakerPreferred = audioSessionController.syncSpeakerPreference()
    }

    private func publishState() {
        delegate?.voiceCallCoordinator(self, didUpdate: state)
    }

    private func logAudioState(_ event: String, extra: String = "") {
        let session = audioSessionController.sessionSnapshot()
        let callFlags = [
            "callPresented=\(state.isPresented)",
            "connection=\(transportState.debugLabel)",
            "callKit=\(callKitEnabled)",
            "muted=\(state.isMicrophoneMuted)",
            "speakerPreferred=\(state.isSpeakerPreferred)",
            "listening=\(state.isListening)",
            "speaking=\(state.isSpeaking)",
            "captureRunning=\(captureEngine.isRunning)",
            "playbackRunning=\(playbackEngine.isRunning)",
            "pendingVoiceStart=\(state.pendingVoiceStart)",
            "captureFromCallKit=\(state.captureStartedFromCallKit)",
            "useVPIO=\(state.useVoiceProcessingInput)"
        ].joined(separator: " ")
        let sessionFlags = [
            "category=\(session.categoryRawValue)",
            "mode=\(session.modeRawValue)",
            "sampleRate=\(Int(session.sampleRate))Hz",
            String(format: "ioBuffer=%.3fms", session.ioBufferDuration * 1000),
            "preferredInput=\(session.preferredInputDescription)",
            "currentRoute=\(audioSessionController.describe(route: session.currentRoute))",
            "availableInputs=\(audioSessionController.describe(route: VoiceAudioRouteSnapshot(inputs: session.availableInputs, outputs: [])).replacingOccurrences(of: "inputs=", with: "").replacingOccurrences(of: " outputs=[]", with: ""))"
        ].joined(separator: " ")
        let suffix = extra.isEmpty ? "" : " \(extra)"
        VoiceDiagnostics.audio("[Audio] \(event)\(suffix) | \(callFlags) | \(sessionFlags)")
    }
}
