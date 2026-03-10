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
    private let eventSink: VoiceCoordinatorEventSink
    private var callKitManager: VoiceCallKitControlling?
    private var audioObservers: [NSObjectProtocol] = []
    private var latestTransportState: VoiceTransportState = .disconnected
    private var currentAudioLevel: Float = 0

    public private(set) var state = VoiceCallUIState()
    public private(set) var callKitEnabled: Bool
    private(set) var callLifecycleState: VoiceCallLifecycleState = .idle
    private(set) var routeLifecycleState: VoiceRouteLifecycleState = .stable(
        RouteContext(
            speakerPreferred: true,
            lastReasonDescription: nil,
            lastShouldAdapt: false,
            lastAdaptationAt: nil
        )
    )

    public convenience init(displayName: String, callKitEnabled: Bool = true) {
        self.init(
            displayName: displayName,
            callKitEnabled: callKitEnabled,
            callKitManager: callKitEnabled ? CallKitManager(appName: displayName) : nil,
            audioSessionController: VoiceAudioSessionController(),
            captureEngine: VoiceCaptureEngine(),
            playbackEngine: VoicePlaybackEngine(),
            eventSink: VoiceDiagnosticsEventSink()
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
        shouldDisableCallKitAfterError: @escaping (Error) -> Bool = CallKitManager.shouldDisableCallKitAfterError,
        eventSink: VoiceCoordinatorEventSink? = nil
    ) {
        self.displayName = displayName
        self.callKitEnabled = callKitEnabled
        self.callKitManager = callKitManager
        self.audioSessionController = audioSessionController
        self.captureEngine = captureEngine
        self.playbackEngine = playbackEngine
        self.describeTransactionError = describeTransactionError
        self.shouldDisableCallKitAfterError = shouldDisableCallKitAfterError
        self.eventSink = eventSink ?? VoiceDiagnosticsEventSink()

        if !callKitEnabled {
            audioSessionController.configureNonCallKitSession(preferSpeaker: state.isSpeakerPreferred)
        }

        syncSpeakerPreferenceFromSession()
        routeLifecycleState = .stable(
            RouteContext(
                speakerPreferred: state.isSpeakerPreferred,
                lastReasonDescription: nil,
                lastShouldAdapt: false,
                lastAdaptationAt: nil
            )
        )

        wireCallbacks()
        observeAudioSession()
        publishState()
    }

    deinit {
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func updateTransportState(_ state: VoiceTransportState) {
        latestTransportState = state
        if callLifecycleState.isPresented {
            refreshLifecycleRuntime()
            publishState()
        }
    }

    public func transportWillConnect() {
        handleEvent(.transportWillConnect)
    }

    public func transportDidFail(message: String) {
        handleEvent(.transportFailed(message: message))
    }

    public func startCall() {
        logAudioState("Voice session start requested")
        handleEvent(.intentStartCall)
        logAudioState("Voice session start finished")
    }

    public func stopCall() {
        logAudioState("Voice session stop requested")
        handleEvent(.intentStopCall)
        logAudioState("Voice session stop finished")
    }

    public func toggleMute() {
        let target = !(callLifecycleState.runtimeContext?.isMuted ?? false)
        handleEvent(.intentToggleMute(isMuted: target))
        logAudioState("Microphone toggle", extra: "isMuted=\(target)")
    }

    public func toggleSpeaker() {
        let shouldPreferSpeaker = !(callLifecycleState.runtimeContext?.speakerPreferred ?? state.isSpeakerPreferred)
        logAudioState(
            "Speaker toggle requested",
            extra: "target=\(shouldPreferSpeaker ? "speaker" : "receiver/system")"
        )
        handleEvent(.intentToggleSpeaker(preferSpeaker: shouldPreferSpeaker))
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
        handleEvent(.transportConnected)
        logAudioState("Gemini delegate connected")
    }

    public func transportDidDisconnect() {
        handleEvent(.transportDisconnected)
        logAudioState("Gemini delegate disconnected", extra: "autoReconnect=true")
    }

    public func transportDidReceiveAudio(_ data: Data) {
        playbackEngine.play(data)
        refreshLifecycleRuntime()
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
        refreshRouteSpeakerPreference()
        publishState()

        guard callLifecycleState.isPresented else { return }

        logAudioState(
            "Route change observed",
            extra: "reason=\(event.reasonDescription) previousRoute=\(event.previousRouteDescription)"
        )

        handleEvent(
            .routeChanged(
                reason: event.reasonDescription,
                previousRouteDescription: event.previousRouteDescription,
                shouldAdapt: event.shouldAdapt
            )
        )
    }

    func handleInterruption(_ event: VoiceInterruptionEvent) {
        switch event.type {
        case .began:
            logAudioState("Audio interruption", extra: "type=\(event.typeDescription)")
            handleEvent(.interruptionBegan)
        case .ended:
            logAudioState(
                "Audio interruption",
                extra: "type=\(event.typeDescription) options=\(event.optionsDescription)"
            )
            handleEvent(.interruptionEnded(shouldResume: event.shouldResume))
        @unknown default:
            break
        }
    }

    private func wireCallbacks() {
        captureEngine.shouldSendAudio = { [weak self] in
            guard let self else { return false }
            guard let runtime = self.callLifecycleState.runtimeContext else { return false }
            return self.callLifecycleState.isPresented &&
                runtime.transportState == .connected &&
                !runtime.isMuted
        }
        captureEngine.onAudioLevel = { [weak self] level in
            guard let self else { return }
            self.currentAudioLevel = level
            self.publishState()
        }
        captureEngine.onAudioData = { [weak self] data in
            self?.onCapturedAudio?(data)
        }
        captureEngine.onVoiceProcessingFallbackRequested = { [weak self] in
            self?.handleEvent(.voiceProcessingFallbackRequested)
        }

        playbackEngine.onSpeakingChanged = { [weak self] isSpeaking in
            guard let self else { return }
            self.eventSink.record(isSpeaking ? .playbackStarted : .playbackStopped)
            self.refreshLifecycleRuntime()
            self.publishState()
        }
        playbackEngine.onRunningChanged = { [weak self] _ in
            guard let self else { return }
            self.refreshLifecycleRuntime()
            self.publishState()
        }

        callKitManager?.onStartAudio = { [weak self] in
            self?.handleEvent(.callKitDidActivate)
        }
        callKitManager?.onStopAudio = { [weak self] in
            self?.handleEvent(.callKitDidDeactivate)
        }
        callKitManager?.onMuteChanged = { [weak self] isMuted in
            self?.handleEvent(.callKitMuteChanged(isMuted: isMuted))
        }
        callKitManager?.onTransactionError = { [weak self] error in
            guard let self else { return }
            let details = self.describeTransactionError(error)
            let disablesCallKit = self.shouldDisableCallKitAfterError(error)
            self.handleEvent(.callKitTransactionFailed(details: details, disablesCallKit: disablesCallKit))
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

    private func handleEvent(_ event: VoiceCoordinatorEvent) {
        eventSink.record(event)
        latestTransportState = transportState(after: event, previous: latestTransportState)

        var effects: [VoiceCoordinatorEffect] = []

        let (nextCallState, callEffects) = reduceCallState(current: callLifecycleState, event: event)
        effects.append(contentsOf: callEffects)
        applyCallState(nextCallState)

        let (nextRouteState, routeEffects) = reduceRouteState(
            current: routeLifecycleState,
            event: event,
            callState: callLifecycleState
        )
        effects.append(contentsOf: routeEffects)
        applyRouteState(nextRouteState)

        runEffects(effects)
        refreshLifecycleRuntime()
        refreshRouteSpeakerPreference()
        publishState()
    }

    private func reduceCallState(
        current: VoiceCallLifecycleState,
        event: VoiceCoordinatorEvent
    ) -> (VoiceCallLifecycleState, [VoiceCoordinatorEffect]) {
        let runtime = runtimeContext(for: current)
        var effects: [VoiceCoordinatorEffect] = []

        switch event {
        case .intentStartCall:
            guard !current.isPresented else { return (current, []) }
            var nextRuntime = initialRuntimeForStart()
            if callKitEnabled {
                effects.append(.startCallKitCall(displayName: displayName))
                if nextRuntime.transportState == .connected {
                    effects.append(.reportCallConnected)
                }
                return (.starting(StartContext(runtime: nextRuntime)), effects)
            }

            effects.append(.configureFallbackSession(preferSpeaker: nextRuntime.speakerPreferred))
            if nextRuntime.transportState == .connected {
                nextRuntime.waitingForTransport = false
                nextRuntime.captureAllowed = !nextRuntime.isMuted
                if !nextRuntime.isMuted {
                    effects.append(.startCapture)
                }
                return (.active(ActiveContext(runtime: nextRuntime)), effects)
            }
            return (.starting(StartContext(runtime: nextRuntime)), effects)

        case .intentStopCall:
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.captureAllowed = false
            nextRuntime.waitingForCallKitActivation = false
            nextRuntime.waitingForTransport = false
            effects.append(.stopCapture)
            effects.append(.stopPlayback(clearQueue: true))
            if callKitEnabled {
                effects.append(.endCallKitCall)
            }
            effects.append(.completeStop)
            return (.stopping(StopContext(runtime: nextRuntime)), effects)

        case .intentToggleMute(let isMuted), .callKitMuteChanged(let isMuted):
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.isMuted = isMuted
            nextRuntime.captureAllowed = !isMuted
            if isMuted {
                effects.append(.stopCapture)
            } else if nextRuntime.transportState == .connected {
                effects.append(.startCapture)
            }
            return (current.replacingRuntime(nextRuntime), effects)

        case .intentToggleSpeaker(let preferSpeaker):
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.speakerPreferred = preferSpeaker
            if callKitEnabled && nextRuntime.captureStartedFromCallKit {
                effects.append(.configureCallKitSession(preferSpeaker: preferSpeaker))
            } else {
                effects.append(.applyOutputOverride(preferSpeaker: preferSpeaker))
            }
            return (current.replacingRuntime(nextRuntime), effects)

        case .transportWillConnect:
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.transportState = .connecting
            nextRuntime.waitingForTransport = true
            if case .failed = current {
                return (.reconnecting(ReconnectContext(runtime: nextRuntime)), effects)
            }
            if case .active = current {
                return (.reconnecting(ReconnectContext(runtime: nextRuntime)), effects)
            }
            return (current.replacingRuntime(nextRuntime), effects)

        case .transportConnected:
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.transportState = .connected
            nextRuntime.waitingForTransport = false
            if callKitEnabled {
                effects.append(.reportCallConnected)
            }
            if !nextRuntime.isMuted && !nextRuntime.captureStartedFromCallKit {
                nextRuntime.captureAllowed = true
                effects.append(.startCapture)
            }
            return (.active(ActiveContext(runtime: nextRuntime)), effects)

        case .transportDisconnected:
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.transportState = .disconnected
            nextRuntime.waitingForTransport = true
            return (.reconnecting(ReconnectContext(runtime: nextRuntime)), effects)

        case .transportFailed(let message):
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.transportState = .error(message)
            nextRuntime.waitingForTransport = true
            return (.failed(FailureContext(runtime: nextRuntime, message: message)), effects)

        case .callKitDidActivate:
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.ownership = .callKit
            nextRuntime.captureStartedFromCallKit = true
            nextRuntime.useVoiceProcessingInput = false
            nextRuntime.captureAllowed = !nextRuntime.isMuted
            nextRuntime.waitingForCallKitActivation = false
            effects.append(.configureCallKitSession(preferSpeaker: nil))
            if !nextRuntime.isMuted {
                effects.append(.startCapture)
            }
            return nextRuntime.transportState == .connected
                ? (.active(ActiveContext(runtime: nextRuntime)), effects)
                : (.starting(StartContext(runtime: nextRuntime)), effects)

        case .callKitDidDeactivate:
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.captureAllowed = false
            nextRuntime.captureStartedFromCallKit = false
            nextRuntime.waitingForCallKitActivation = callKitEnabled
            effects.append(.stopCapture)
            return nextRuntime.transportState == .connected
                ? (.starting(StartContext(runtime: nextRuntime)), effects)
                : (.reconnecting(ReconnectContext(runtime: nextRuntime)), effects)

        case .callKitTransactionFailed(let details, let disablesCallKit):
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.ownership = .direct
            nextRuntime.captureStartedFromCallKit = false
            nextRuntime.useVoiceProcessingInput = false
            nextRuntime.captureAllowed = !nextRuntime.isMuted
            nextRuntime.waitingForCallKitActivation = false
            effects.append(.configureFallbackSession(preferSpeaker: nextRuntime.speakerPreferred))
            if disablesCallKit {
                effects.append(.disableCallKit)
                effects.append(.notifyDelegateCallKitEnabled(false))
            }
            switch nextRuntime.transportState {
            case .connected:
                if !nextRuntime.isMuted {
                    effects.append(.startCapture)
                }
                return (.active(ActiveContext(runtime: nextRuntime)), effects)
            case .connecting, .disconnected:
                nextRuntime.waitingForTransport = true
                return (.reconnecting(ReconnectContext(runtime: nextRuntime)), effects)
            case .error:
                nextRuntime.waitingForTransport = true
                return (.failed(FailureContext(runtime: nextRuntime, message: details)), effects)
            }

        case .voiceProcessingFallbackRequested:
            guard current.isPresented else { return (current, []) }
            var nextRuntime = runtime
            nextRuntime.useVoiceProcessingInput = false
            effects.append(.restartCaptureForFallback)
            return (current.replacingRuntime(nextRuntime), effects)

        case .captureStarted:
            guard current.isPresented else { return (current, []) }
            return (current.replacingRuntime(runtime), effects)

        case .captureStopped, .playbackStarted, .playbackStopped, .routeChanged, .routeAdaptationStarted,
                .routeAdaptationFinished, .routeAdaptationSkipped, .interruptionBegan, .interruptionEnded,
                .stateTransition, .routeStateTransition:
            return (current, effects)
        }
    }

    private func reduceRouteState(
        current: VoiceRouteLifecycleState,
        event: VoiceCoordinatorEvent,
        callState: VoiceCallLifecycleState
    ) -> (VoiceRouteLifecycleState, [VoiceCoordinatorEffect]) {
        var base = current.baseContext
        if let runtime = callState.runtimeContext {
            base.speakerPreferred = runtime.speakerPreferred
        }
        var effects: [VoiceCoordinatorEffect] = []

        switch event {
        case .intentToggleSpeaker(let preferSpeaker):
            base.speakerPreferred = preferSpeaker
            return (.stable(base), effects)

        case .routeChanged(let reason, let previousRouteDescription, let shouldAdapt):
            base.lastReasonDescription = reason
            base.lastShouldAdapt = shouldAdapt
            base.speakerPreferred = audioSessionController.syncSpeakerPreference()

            let shouldAdaptRoute: Bool
            if callKitEnabled {
                shouldAdaptRoute = shouldAdapt && !(callState.runtimeContext?.useVoiceProcessingInput ?? true)
            } else {
                shouldAdaptRoute = shouldAdapt
            }

            if callKitEnabled && !shouldAdaptRoute {
                if shouldAdapt || reason == "override" {
                    effects.append(.resetIdlePlaybackGraph(reason: reason))
                    logAudioState("Route change ignored because CallKit owns session", extra: "reason=\(reason)")
                }
                return (.stable(base), effects)
            }

            guard shouldAdaptRoute, callState.isPresented else {
                return (.stable(base), effects)
            }

            if case .adapting = current {
                eventSink.record(.routeAdaptationSkipped(reason: "already-adapting"))
                return (.blocked(RouteBlockContext(base: base, reasonDescription: "already-adapting")), effects)
            }

            if let lastAdaptationAt = current.lastAdaptationAt,
               Date().timeIntervalSince(lastAdaptationAt) < 1.0 {
                eventSink.record(.routeAdaptationSkipped(reason: "debounced"))
                return (.blocked(RouteBlockContext(base: base, reasonDescription: "debounced")), effects)
            }

            let shouldResumeCapture = callState.isPresented &&
                callState.transportState == .connected &&
                !(callState.runtimeContext?.isMuted ?? false) &&
                captureEngine.isRunning
            let shouldResumePlayback = playbackEngine.isRunning ||
                playbackEngine.enqueuedBufferCount > 0 ||
                playbackEngine.isSpeaking

            guard shouldResumeCapture || shouldResumePlayback else {
                return (.stable(base), effects)
            }

            let adaptation = RouteAdaptationContext(
                base: base,
                reasonDescription: reason,
                previousRouteDescription: previousRouteDescription,
                resumeCapture: shouldResumeCapture,
                resumePlayback: shouldResumePlayback
            )
            effects.append(.performRouteAdaptation(adaptation))
            return (.adapting(adaptation), effects)

        case .interruptionBegan:
            return (.interrupted(InterruptionContext(base: base, shouldResume: false)), !callKitEnabled ? [.stopCapture] : effects)

        case .interruptionEnded(let shouldResume):
            base.lastReasonDescription = "interruptionEnded"
            if shouldResume && callState.isPresented && !callKitEnabled && !(callState.runtimeContext?.isMuted ?? false) {
                effects.append(.startCapture)
            }
            return (.stable(base), effects)

        case .routeAdaptationFinished:
            base.lastAdaptationAt = Date()
            return (.stable(base), effects)

        case .routeAdaptationStarted, .routeAdaptationSkipped, .intentStartCall, .intentStopCall,
                .intentToggleMute, .transportWillConnect, .transportConnected, .transportDisconnected,
                .transportFailed, .callKitDidActivate, .callKitDidDeactivate, .callKitMuteChanged,
                .callKitTransactionFailed, .voiceProcessingFallbackRequested, .captureStarted,
                .captureStopped, .playbackStarted, .playbackStopped, .stateTransition, .routeStateTransition:
            return (current, effects)
        }
    }

    private func runEffects(_ effects: [VoiceCoordinatorEffect]) {
        for effect in effects {
            switch effect {
            case .startCallKitCall(let displayName):
                callKitManager?.startCall(displayName: displayName)

            case .endCallKitCall:
                callKitManager?.endCall()

            case .reportCallConnected:
                callKitManager?.reportConnected()

            case .configureCallKitSession(let preferSpeaker):
                captureEngine.useVoiceProcessingInput = false
                audioSessionController.configureActiveCallKitSession(preferSpeaker: preferSpeaker)
                syncSpeakerPreferenceFromSession()
                let label = preferSpeaker.map { $0 ? "speaker" : "receiver/system" } ?? "preserve"
                logAudioState("CallKit session configured", extra: "mode=voiceChat speakerOverride=\(label)")

            case .configureFallbackSession(let preferSpeaker):
                if let shouldUseVoiceProcessingInput = callLifecycleState.runtimeContext?.useVoiceProcessingInput {
                    captureEngine.useVoiceProcessingInput = shouldUseVoiceProcessingInput
                }
                audioSessionController.configureNonCallKitSession(preferSpeaker: preferSpeaker)
                syncSpeakerPreferenceFromSession()
                logAudioState("Started direct audio fallback path")

            case .applyOutputOverride(let preferSpeaker):
                do {
                    try audioSessionController.applyOutputOverride(preferSpeaker: preferSpeaker)
                } catch {
                    VoiceDiagnostics.fault("[Audio] Speaker toggle failed error=\(error.localizedDescription)")
                }
                syncSpeakerPreferenceFromSession()

            case .startCapture:
                startCaptureIfNeeded()

            case .stopCapture:
                stopCapture()

            case .restartCaptureForFallback:
                stopCapture()
                if shouldStartCaptureNow {
                    startCaptureIfNeeded()
                }

            case .stopPlayback(let clearQueue):
                stopPlayback(clearQueue: clearQueue)

            case .preparePlayback:
                playbackEngine.prepareIfNeeded()
                refreshLifecycleRuntime()

            case .resetIdlePlaybackGraph(let reason):
                playbackEngine.resetIdleGraphForRouteChange(reason: reason)
                refreshLifecycleRuntime()

            case .performRouteAdaptation(let context):
                eventSink.record(.routeAdaptationStarted(
                    resumeCapture: context.resumeCapture,
                    resumePlayback: context.resumePlayback
                ))
                logAudioState(
                    "Route adaptation started",
                    extra: "resumeCapture=\(context.resumeCapture) resumePlayback=\(context.resumePlayback)"
                )
                stopCapture()
                stopPlayback(clearQueue: false)
                if context.resumeCapture {
                    startCaptureIfNeeded()
                }
                if context.resumePlayback {
                    playbackEngine.prepareIfNeeded()
                    refreshLifecycleRuntime()
                }
                var stable = context.base
                stable.lastAdaptationAt = Date()
                applyRouteState(.stable(stable))
                eventSink.record(.routeAdaptationFinished)
                logAudioState("Route adaptation finished")

            case .disableCallKit:
                disableCallKitForSession()

            case .notifyDelegateCallKitEnabled(let isEnabled):
                delegate?.voiceCallCoordinator(self, didChangeCallKitEnabled: isEnabled)

            case .completeStop:
                applyCallState(.idle)
            }
        }
    }

    private var shouldStartCaptureNow: Bool {
        guard let runtime = callLifecycleState.runtimeContext else { return false }
        return callLifecycleState.isPresented && runtime.transportState == .connected && !runtime.isMuted
    }

    private func initialRuntimeForStart() -> VoiceCallRuntimeContext {
        VoiceCallRuntimeContext(
            ownership: callKitEnabled ? .callKit : .direct,
            captureAllowed: false,
            captureStartedFromCallKit: false,
            transportState: latestTransportState,
            isMuted: false,
            isPlaybackActive: playbackEngine.isRunning || playbackEngine.isSpeaking,
            useVoiceProcessingInput: captureEngine.useVoiceProcessingInput,
            waitingForCallKitActivation: callKitEnabled,
            waitingForTransport: latestTransportState != .connected,
            speakerPreferred: state.isSpeakerPreferred
        )
    }

    private func runtimeContext(for current: VoiceCallLifecycleState) -> VoiceCallRuntimeContext {
        current.runtimeContext ?? VoiceCallRuntimeContext(
            ownership: callKitEnabled ? .callKit : .direct,
            captureAllowed: false,
            captureStartedFromCallKit: false,
            transportState: latestTransportState,
            isMuted: false,
            isPlaybackActive: playbackEngine.isRunning || playbackEngine.isSpeaking,
            useVoiceProcessingInput: captureEngine.useVoiceProcessingInput,
            waitingForCallKitActivation: false,
            waitingForTransport: false,
            speakerPreferred: state.isSpeakerPreferred
        )
    }

    private func transportState(after event: VoiceCoordinatorEvent, previous: VoiceTransportState) -> VoiceTransportState {
        switch event {
        case .transportWillConnect:
            return .connecting
        case .transportConnected:
            return .connected
        case .transportDisconnected:
            return .disconnected
        case .transportFailed(let message):
            return .error(message)
        default:
            return previous
        }
    }

    private func refreshLifecycleRuntime() {
        guard var runtime = callLifecycleState.runtimeContext else { return }
        runtime.transportState = latestTransportState
        runtime.captureStartedFromCallKit = runtime.captureStartedFromCallKit && callKitEnabled
        runtime.isPlaybackActive = playbackEngine.isRunning || playbackEngine.isSpeaking
        runtime.useVoiceProcessingInput = captureEngine.useVoiceProcessingInput
        runtime.speakerPreferred = audioSessionController.syncSpeakerPreference()
        applyCallState(callLifecycleState.replacingRuntime(runtime), recordTransition: false)
    }

    private func refreshRouteSpeakerPreference() {
        var base = routeLifecycleState.baseContext
        base.speakerPreferred = audioSessionController.syncSpeakerPreference()
        switch routeLifecycleState {
        case .stable:
            applyRouteState(.stable(base), recordTransition: false)
        case .blocked(let context):
            applyRouteState(.blocked(RouteBlockContext(base: base, reasonDescription: context.reasonDescription)), recordTransition: false)
        case .interrupted(let context):
            applyRouteState(.interrupted(InterruptionContext(base: base, shouldResume: context.shouldResume)), recordTransition: false)
        case .adapting(let context):
            applyRouteState(
                .adapting(
                    RouteAdaptationContext(
                        base: base,
                        reasonDescription: context.reasonDescription,
                        previousRouteDescription: context.previousRouteDescription,
                        resumeCapture: context.resumeCapture,
                        resumePlayback: context.resumePlayback
                    )
                ),
                recordTransition: false
            )
        }
    }

    private func startCaptureIfNeeded() {
        let hadEngine = captureEngine.isRunning
        captureEngine.start()
        if !hadEngine && captureEngine.isRunning {
            eventSink.record(.captureStarted)
        }
        refreshLifecycleRuntime()
    }

    private func stopCapture() {
        let hadEngine = captureEngine.isRunning
        let metrics = captureEngine.stop()
        if hadEngine {
            eventSink.record(.captureStopped)
        }
        currentAudioLevel = 0
        refreshLifecycleRuntime()
        logAudioState(
            hadEngine ? "Capture stopped" : "Capture stop requested with no active engine",
            extra: "callbacks=\(metrics.callbackCount) chunks=\(metrics.chunkCount) bytes=\(metrics.byteCount)"
        )
    }

    private func stopPlayback(clearQueue: Bool) {
        let wasRunning = playbackEngine.isRunning || playbackEngine.isSpeaking
        playbackEngine.stop(clearQueue: clearQueue)
        if wasRunning {
            eventSink.record(.playbackStopped)
        }
        refreshLifecycleRuntime()
    }

    private func disableCallKitForSession() {
        guard callKitEnabled else { return }
        callKitEnabled = false
        callKitManager?.onStartAudio = nil
        callKitManager?.onStopAudio = nil
        callKitManager?.onMuteChanged = nil
        callKitManager?.onTransactionError = nil
        callKitManager = nil
        logAudioState("CallKit disabled for current session")
    }

    private func syncSpeakerPreferenceFromSession() {
        state.isSpeakerPreferred = audioSessionController.syncSpeakerPreference()
    }

    private func deriveUIState() -> VoiceCallUIState {
        var next = state
        let runtime = callLifecycleState.runtimeContext
        next.isPresented = callLifecycleState.isPresented
        next.audioLevel = callLifecycleState.isPresented ? currentAudioLevel : 0
        next.isMicrophoneMuted = runtime?.isMuted ?? false
        next.isSpeakerPreferred = runtime?.speakerPreferred ?? audioSessionController.syncSpeakerPreference()
        next.pendingVoiceStart = runtime?.waitingForCallKitActivation == true || runtime?.waitingForTransport == true
        next.captureStartedFromCallKit = runtime?.captureStartedFromCallKit ?? false
        next.useVoiceProcessingInput = runtime?.useVoiceProcessingInput ?? captureEngine.useVoiceProcessingInput
        next.isCaptureRunning = captureEngine.isRunning
        next.isPlaybackRunning = playbackEngine.isRunning
        next.isSpeaking = playbackEngine.isSpeaking
        next.isListening = deriveListeningState(runtime: runtime)
        return next
    }

    private func deriveListeningState(runtime: VoiceCallRuntimeContext?) -> Bool {
        guard let runtime, callLifecycleState.isPresented else { return false }
        guard !runtime.isMuted else { return false }
        guard audioSessionController.currentRouteHasOutputs() else { return false }
        if runtime.captureStartedFromCallKit && captureEngine.isRunning {
            return true
        }
        if runtime.waitingForCallKitActivation {
            return false
        }
        if runtime.waitingForTransport {
            return false
        }
        return captureEngine.isRunning
    }

    private func publishState() {
        state = deriveUIState()
        delegate?.voiceCallCoordinator(self, didUpdate: state)
    }

    private func applyCallState(_ next: VoiceCallLifecycleState, recordTransition: Bool = true) {
        let previous = callLifecycleState
        callLifecycleState = next
        if recordTransition && previous != next {
            eventSink.record(.stateTransition(from: previous, to: next))
        }
    }

    private func applyRouteState(_ next: VoiceRouteLifecycleState, recordTransition: Bool = true) {
        let previous = routeLifecycleState
        routeLifecycleState = next
        if recordTransition && previous != next {
            eventSink.record(.routeStateTransition(from: previous, to: next))
        }
    }

    private func logAudioState(_ event: String, extra: String = "") {
        let session = audioSessionController.sessionSnapshot()
        let callFlags = [
            "callPresented=\(callLifecycleState.isPresented)",
            "connection=\(latestTransportState.debugLabel)",
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
