import XCTest
@preconcurrency import AVFoundation
@testable import VoiceCore

@MainActor
final class VoiceCallCoordinatorTests: XCTestCase {
    func testStartCallWithCallKitQueuesPendingStartAndInvokesCallKit() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.startCall()

        XCTAssertTrue(harness.coordinator.state.isPresented)
        XCTAssertTrue(harness.coordinator.state.pendingVoiceStart)
        XCTAssertEqual(harness.callKit.startCallCount, 1)
        XCTAssertEqual(harness.coordinator.callLifecycleState.debugLabel, "starting(callKit,disconnected,awaitingCallKit,awaitingTransport)")
    }

    func testTransportConnectStartsDirectCaptureAndClearsPendingStart() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.startCall()
        XCTAssertTrue(harness.coordinator.state.pendingVoiceStart)

        harness.coordinator.transportDidConnect()

        XCTAssertEqual(harness.capture.startCount, 1)
        XCTAssertFalse(harness.coordinator.state.pendingVoiceStart)
        XCTAssertTrue(harness.coordinator.state.isListening)
        XCTAssertEqual(harness.coordinator.callLifecycleState.debugLabel, "active(direct,connected)")
    }

    func testUnmuteRestartsCaptureWhenCallIsActive() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        XCTAssertEqual(harness.capture.startCount, 1)

        harness.coordinator.toggleMute()
        harness.capture.isRunning = false

        harness.coordinator.toggleMute()

        XCTAssertEqual(harness.capture.startCount, 2)
        XCTAssertFalse(harness.coordinator.state.isMicrophoneMuted)
        XCTAssertEqual(harness.coordinator.callLifecycleState.runtimeContext?.isMuted, false)
    }

    func testSpeakerToggleUsesCallKitSessionControllerWhenCallKitOwnsAudio() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.coordinator.toggleSpeaker()

        XCTAssertEqual(harness.audioSession.callKitSpeakerOverrides, [nil, true])
        XCTAssertTrue(harness.coordinator.state.isSpeakerPreferred)
        XCTAssertEqual(harness.coordinator.routeLifecycleState.baseContext.speakerPreferred, true)
    }

    func testOverrideRouteChangeRebuildsGraphsForCallKitFallbackPath() {
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

        XCTAssertEqual(harness.capture.stopCount, 1)
        XCTAssertEqual(harness.capture.startCount, 2)
        XCTAssertEqual(harness.playback.stopCount, 1)
        XCTAssertEqual(harness.playback.prepareCount, 1)
        XCTAssertEqual(harness.coordinator.routeLifecycleState.debugLabel, "stable(speaker=false, reason=override)")
    }

    func testStartCallWithoutCallKitButConnectedTransportTransitionsDirectlyToActive() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()

        XCTAssertEqual(harness.coordinator.callLifecycleState.debugLabel, "active(direct,connected)")
        XCTAssertEqual(harness.audioSession.directSpeakerPreferences, [true, true])
        XCTAssertEqual(harness.capture.startCount, 1)
    }

    func testTransportFailureTransitionsToFailedState() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.startCall()
        harness.coordinator.transportDidFail(message: "socket")

        XCTAssertEqual(harness.coordinator.callLifecycleState.debugLabel, "failed(direct,error(socket),awaitingTransport, message=socket)")
    }

    func testTransportWillConnectFromFailureTransitionsToReconnecting() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.startCall()
        harness.coordinator.transportDidFail(message: "socket")
        harness.coordinator.transportWillConnect()

        XCTAssertEqual(harness.coordinator.callLifecycleState.debugLabel, "reconnecting(direct,connecting,awaitingTransport)")
    }

    func testCallKitDeactivateTransitionsBackToWaitingForActivation() {
        let harness = CoordinatorHarness(callKitEnabled: true)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.capture.isRunning = true

        harness.callKit.onStopAudio?()

        XCTAssertEqual(harness.capture.stopCount, 1)
        XCTAssertEqual(harness.coordinator.callLifecycleState.debugLabel, "starting(callKit,connected,awaitingCallKit,fallbackInput)")
    }

    func testCallKitTransactionFailureDisablesCallKitAndFallsBackToDirectAudio() {
        let harness = CoordinatorHarness(callKitEnabled: true, disableCallKitAfterError: true)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()
        harness.callKit.onStartAudio?()
        harness.callKit.onTransactionError?(MockError())

        XCTAssertFalse(harness.coordinator.callKitEnabled)
        XCTAssertEqual(harness.audioSession.directSpeakerPreferences.last, false)
        XCTAssertEqual(harness.coordinator.callLifecycleState.debugLabel, "active(direct,connected,fallbackInput)")
        XCTAssertEqual(harness.delegate.callKitEnabledChanges, [false])
    }

    func testRouteChangeDebounceTransitionsRouteStateToBlocked() {
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

        XCTAssertEqual(harness.coordinator.routeLifecycleState.debugLabel, "blocked(reason=debounced)")
        XCTAssertTrue(harness.eventSink.events.contains(.routeAdaptationSkipped(reason: "debounced")))
    }

    func testInterruptionEndedWithoutResumeLeavesCaptureStopped() {
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

        XCTAssertEqual(harness.capture.stopCount, 1)
        XCTAssertFalse(harness.coordinator.state.isListening)
        XCTAssertFalse(harness.capture.isRunning)
    }

    func testEventSinkRecordsCallStateTransitionsForCallStart() {
        let harness = CoordinatorHarness(callKitEnabled: false)

        harness.coordinator.transportDidConnect()
        harness.coordinator.startCall()

        XCTAssertTrue(harness.eventSink.events.contains {
            if case .stateTransition(let from, let to) = $0 {
                return from == .idle && to.debugLabel == "active(direct,connected)"
            }
            return false
        })
    }

    func testEventSinkRecordsRouteAdaptationLifecycle() {
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

        XCTAssertTrue(harness.eventSink.events.contains(.routeAdaptationStarted(resumeCapture: true, resumePlayback: true)))
        XCTAssertTrue(harness.eventSink.events.contains(.routeAdaptationFinished))
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
