import Testing
@preconcurrency import AVFoundation
@testable import VoiceCore

@Suite(.tags(.voicecore))
@MainActor
struct VoiceCallCoordinatorTests {
    @Test
    func startCallWithCallKitQueuesPendingStartAndInvokesCallKit() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.startCall()

        #expect(harness.coordinator.state.isPresented)
        #expect(harness.coordinator.state.pendingVoiceStart)
        #expect(harness.callKit.startCallCount == 1)
        expectCallLifecycleState(
            harness.coordinator,
            equals: "starting(callKit,disconnected,awaitingCallKit,awaitingTransport)"
        )
    }

    @Test
    func transportConnectStartsDirectCaptureAndClearsPendingStart() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.startCall()
        #expect(harness.coordinator.state.pendingVoiceStart)

        harness.coordinator.transportDidConnect()

        #expect(harness.capture.startCount == 1)
        #expect(harness.coordinator.state.pendingVoiceStart == false)
        #expect(harness.coordinator.state.isListening)
        expectCallLifecycleState(harness.coordinator, equals: "active(direct,connected)")
    }

    @Test
    func unmuteRestartsCaptureWhenCallIsActive() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        #expect(harness.capture.startCount == 1)

        harness.coordinator.toggleMute()
        harness.capture.isRunning = false

        harness.coordinator.toggleMute()

        #expect(harness.capture.startCount == 2)
        #expect(harness.coordinator.state.isMicrophoneMuted == false)
        #expect(harness.coordinator.callLifecycleState.runtimeContext?.isMuted == false)
    }

    @Test
    func speakerToggleUsesCallKitSessionControllerWhenCallKitOwnsAudio() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.coordinator.toggleSpeaker()

        #expect(harness.audioSession.callKitSpeakerOverrides == [nil, true])
        #expect(harness.coordinator.state.isSpeakerPreferred)
        #expect(harness.coordinator.routeLifecycleState.baseContext.speakerPreferred == true)
    }

    @Test
    func overrideRouteChangeRebuildsGraphsForCallKitFallbackPath() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.capture.isRunning = true
        harness.playback.isRunning = true
        harness.playback.isSpeaking = true

        harness.coordinator.handleRouteChange(
            VoiceRouteChangeEvent(
                reason: .override,
                reasonDescription: "override",
                previousRouteDescription: "inputs=[] outputs=[]",
                shouldAdapt: true
            )
        )

        #expect(harness.capture.stopCount == 1)
        #expect(harness.capture.startCount == 2)
        #expect(harness.playback.stopCount == 1)
        #expect(harness.playback.prepareCount == 1)
        expectRouteLifecycleState(
            harness.coordinator,
            equals: "stable(speaker=false, reason=override)"
        )
    }

    @Test
    func startCallWithoutCallKitButConnectedTransportTransitionsDirectlyToActive() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()

        expectCallLifecycleState(harness.coordinator, equals: "active(direct,connected)")
        #expect(harness.audioSession.directSpeakerPreferences == [true, true])
        #expect(harness.capture.startCount == 1)
    }

    @Test
    func transportFailureTransitionsToFailedState() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.startCall()
        harness.coordinator.transportDidFail(message: "socket")

        expectCallLifecycleState(
            harness.coordinator,
            equals: "failed(direct,error(socket),awaitingTransport, message=socket)"
        )
    }

    @Test
    func transportWillConnectFromFailureTransitionsToReconnecting() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.startCall()
        harness.coordinator.transportDidFail(message: "socket")
        harness.coordinator.transportWillConnect()

        expectCallLifecycleState(
            harness.coordinator,
            equals: "reconnecting(direct,connecting,awaitingTransport)"
        )
    }

    @Test
    func callKitDeactivateTransitionsBackToWaitingForActivation() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.capture.isRunning = true

        harness.callKit.onStopAudio?()

        #expect(harness.capture.stopCount == 1)
        expectCallLifecycleState(
            harness.coordinator,
            equals: "starting(callKit,connected,awaitingCallKit,fallbackInput)"
        )
    }

    @Test
    func callKitTransactionFailureDisablesCallKitAndFallsBackToDirectAudio() {
        let harness = CoordinatorHarness(callKitEnabled: true, disableCallKitAfterError: true)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.callKit.onTransactionError?(MockError())

        #expect(harness.coordinator.callKitEnabled == false)
        #expect(harness.audioSession.directSpeakerPreferences.last == false)
        expectCallLifecycleState(
            harness.coordinator,
            equals: "active(direct,connected,fallbackInput)"
        )
        #expect(harness.delegate.callKitEnabledChanges == [false])
    }

    @Test
    func routeChangeDebounceTransitionsRouteStateToBlocked() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.capture.isRunning = true
        harness.playback.isRunning = true

        let event = VoiceRouteChangeEvent(
            reason: .override,
            reasonDescription: "override",
            previousRouteDescription: "inputs=[] outputs=[]",
            shouldAdapt: true
        )

        harness.coordinator.handleRouteChange(event)
        harness.capture.isRunning = true
        harness.playback.isRunning = true
        harness.coordinator.handleRouteChange(event)

        expectRouteLifecycleState(harness.coordinator, equals: "blocked(reason=debounced)")
        #expect(harness.eventSink.events.contains(.routeAdaptationSkipped(reason: "debounced")))
    }

    @Test
    func interruptionEndedWithoutResumeLeavesCaptureStopped() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.capture.isRunning = true

        harness.coordinator.handleInterruption(
            VoiceInterruptionEvent(
                type: .began,
                typeDescription: "began",
                options: [],
                optionsDescription: "[]"
            )
        )
        harness.coordinator.handleInterruption(
            VoiceInterruptionEvent(
                type: .ended,
                typeDescription: "ended",
                options: [],
                optionsDescription: "[]"
            )
        )

        #expect(harness.capture.stopCount == 1)
        #expect(harness.coordinator.state.isListening == false)
        #expect(harness.capture.isRunning == false)
    }

    @Test
    func eventSinkRecordsCallStateTransitionsForCallStart() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()

        #expect(harness.eventSink.events.contains {
            if case .stateTransition(let from, let to) = $0 {
                return from == .idle && to.debugLabel == "active(direct,connected)"
            }
            return false
        })
    }

    @Test
    func eventSinkRecordsRouteAdaptationLifecycle() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.capture.isRunning = true
        harness.playback.isRunning = true

        harness.coordinator.handleRouteChange(
            VoiceRouteChangeEvent(
                reason: .override,
                reasonDescription: "override",
                previousRouteDescription: "inputs=[] outputs=[]",
                shouldAdapt: true
            )
        )

        #expect(
            harness.eventSink.events.contains(
                .routeAdaptationStarted(resumeCapture: true, resumePlayback: true)
            )
        )
        #expect(harness.eventSink.events.contains(.routeAdaptationFinished))
    }
}

@MainActor
private final class CoordinatorHarness {
    let callKit = MockCallKitManager()
    let audioSession = MockAudioSessionController()
    let capture = MockCaptureEngine()
    let playback = MockPlaybackEngine()
    let eventSink = MockEventSink()
    let delegate = MockCoordinatorDelegate()
    let coordinator: VoiceCallCoordinator

    init(callKitEnabled: Bool, disableCallKitAfterError: Bool = false) {
        coordinator = VoiceCallCoordinator(
            displayName: "Heard, Chef",
            callKitEnabled: callKitEnabled,
            callKitManager: callKitEnabled ? callKit : nil,
            audioSessionController: audioSession,
            captureEngine: capture,
            playbackEngine: playback,
            describeTransactionError: { _ in "mock" },
            shouldDisableCallKitAfterError: { _ in disableCallKitAfterError },
            eventSink: eventSink
        )
        coordinator.delegate = delegate
    }
}

@MainActor
private final class MockCoordinatorDelegate: VoiceCallCoordinatorDelegate {
    private(set) var updates: [VoiceCallUIState] = []
    private(set) var callKitEnabledChanges: [Bool] = []

    func voiceCallCoordinator(_ coordinator: VoiceCallCoordinator, didUpdate state: VoiceCallUIState) {
        _ = coordinator
        updates.append(state)
    }

    func voiceCallCoordinator(_ coordinator: VoiceCallCoordinator, didChangeCallKitEnabled isEnabled: Bool) {
        _ = coordinator
        callKitEnabledChanges.append(isEnabled)
    }
}

@MainActor
private final class MockEventSink: VoiceCoordinatorEventSink {
    private(set) var events: [VoiceCoordinatorEvent] = []

    func record(_ event: VoiceCoordinatorEvent) {
        events.append(event)
    }
}

@MainActor
private final class MockCallKitManager: VoiceCallKitControlling {
    var onStartAudio: (() -> Void)?
    var onStopAudio: (() -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onTransactionError: ((Error) -> Void)?

    private(set) var startCallCount = 0
    private(set) var endCallCount = 0
    private(set) var reportConnectedCount = 0

    func startCall(displayName: String) {
        _ = displayName
        startCallCount += 1
    }

    func endCall() {
        endCallCount += 1
    }

    func reportConnected() {
        reportConnectedCount += 1
    }
}

@MainActor
private final class MockAudioSessionController: VoiceAudioSessionControlling {
    var speakerPreferred = false
    var currentRouteOutputs = true
    private(set) var directSpeakerPreferences: [Bool] = []
    private(set) var callKitSpeakerOverrides: [Bool?] = []
    private(set) var outputOverridePreferences: [Bool] = []

    func configureNonCallKitSession(preferSpeaker: Bool) {
        directSpeakerPreferences.append(preferSpeaker)
        speakerPreferred = preferSpeaker
    }

    func configureActiveCallKitSession(preferSpeaker: Bool?) {
        callKitSpeakerOverrides.append(preferSpeaker)
        if let preferSpeaker {
            speakerPreferred = preferSpeaker
        }
    }

    func applyOutputOverride(preferSpeaker: Bool) throws {
        outputOverridePreferences.append(preferSpeaker)
        speakerPreferred = preferSpeaker
    }

    func syncSpeakerPreference() -> Bool {
        speakerPreferred
    }

    func currentRouteHasOutputs() -> Bool {
        currentRouteOutputs
    }

    func sessionSnapshot() -> VoiceAudioSessionSnapshot {
        VoiceAudioSessionSnapshot(
            categoryRawValue: "AVAudioSessionCategoryPlayAndRecord",
            modeRawValue: "AVAudioSessionModeVoiceChat",
            sampleRate: 48_000,
            ioBufferDuration: 0.023,
            preferredInputDescription: "none",
            currentRoute: VoiceAudioRouteSnapshot(inputs: [], outputs: []),
            availableInputs: []
        )
    }

    func routeChangeEvent(from notification: Notification) -> VoiceRouteChangeEvent {
        _ = notification
        return VoiceRouteChangeEvent(
            reason: .override,
            reasonDescription: "override",
            previousRouteDescription: "inputs=[] outputs=[]",
            shouldAdapt: true
        )
    }

    func interruptionEvent(from notification: Notification) -> VoiceInterruptionEvent? {
        _ = notification
        return nil
    }

    func describe(route: VoiceAudioRouteSnapshot?) -> String {
        guard let route else { return "inputs=[] outputs=[]" }
        let inputs = route.inputs.map(\.description).joined(separator: ", ")
        let outputs = route.outputs.map(\.description).joined(separator: ", ")
        return "inputs=[\(inputs)] outputs=[\(outputs)]"
    }
}

@MainActor
private final class MockCaptureEngine: VoiceCaptureHandling {
    var isRunning = false
    var useVoiceProcessingInput = true
    var metrics = VoiceCaptureMetrics()
    var consecutiveSilentStops = 0
    var onAudioLevel: ((Float) -> Void)?
    var onAudioData: ((Data) -> Void)?
    var shouldSendAudio: (() -> Bool)?
    var onVoiceProcessingFallbackRequested: (() -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
        isRunning = true
    }

    func stop() -> VoiceCaptureMetrics {
        stopCount += 1
        isRunning = false
        return metrics
    }

    func processAudioBufferForTesting(_ buffer: AVAudioPCMBuffer) {
        _ = buffer
    }

    func prepareConverterForTesting(inputFormat: AVAudioFormat) {
        _ = inputFormat
    }
}

@MainActor
private final class MockPlaybackEngine: VoicePlaybackHandling {
    var isRunning = false
    var isSpeaking = false
    var enqueuedBufferCount = 0
    var onSpeakingChanged: ((Bool) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?

    private(set) var playCount = 0
    private(set) var prepareCount = 0
    private(set) var stopCount = 0

    func play(_ data: Data) {
        _ = data
        playCount += 1
        isRunning = true
        isSpeaking = true
        onRunningChanged?(true)
        onSpeakingChanged?(true)
    }

    func prepareIfNeeded() {
        prepareCount += 1
        isRunning = true
        onRunningChanged?(true)
    }

    func stop(clearQueue: Bool) {
        _ = clearQueue
        stopCount += 1
        isRunning = false
        isSpeaking = false
        if clearQueue {
            enqueuedBufferCount = 0
        }
        onSpeakingChanged?(false)
        onRunningChanged?(false)
    }

    func resetIdleGraphForRouteChange(reason: String) {
        _ = reason
    }

    func simulateScheduledBufferForTesting() {}

    func simulatePlaybackCompletionForTesting() {}
}

private struct MockError: Error {}
