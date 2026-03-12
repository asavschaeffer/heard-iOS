import Testing
@preconcurrency import AVFoundation
@testable import VoiceCore

@Suite(.tags(.voicecore))
@MainActor
struct VoiceAudioSessionControllerTests {
    @Test
    func configureActiveCallKitSessionForSpeakerOverridesSpeakerAndClearsPreferredInput() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureActiveCallKitSession(preferSpeaker: true)

        #expect(session.lastCategory == .playAndRecord)
        #expect(session.lastMode == .voiceChat)
        #expect(session.lastOverride == .speaker)
        #expect(session.lastPreferredInput == VoiceAudioInputPreference.none)
    }

    @Test
    func configureActiveCallKitSessionForReceiverPrefersBuiltInMic() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureActiveCallKitSession(preferSpeaker: false)

        #expect(session.lastOverride == AVAudioSession.PortOverride.none)
        #expect(session.lastPreferredInput == .builtInMic)
    }

    @Test
    func configureNonCallKitSessionForReceiverAvoidsDefaultToSpeaker() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureNonCallKitSession(preferSpeaker: false)

        #expect(session.lastCategory == .playAndRecord)
        #expect(session.lastMode == .voiceChat)
        #expect(session.lastOptions?.contains(.defaultToSpeaker) == false)
        #expect(session.lastPreferredInput == .builtInMic)
    }

    @Test
    func configureNonCallKitSessionPrefersEchoCancelledInputWhenAvailable() {
        let session = MockVoiceAudioSessionClient()
        session.isEchoCancelledInputAvailable = true
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureNonCallKitSession(preferSpeaker: true)

        #expect(session.lastPrefersEchoCancelledInput == true)
    }

    @Test
    func configureNonCallKitSessionSkipsEchoCancelledPreferenceWhenUnavailable() {
        let session = MockVoiceAudioSessionClient()
        session.isEchoCancelledInputAvailable = false
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureNonCallKitSession(preferSpeaker: true)

        #expect(session.lastPrefersEchoCancelledInput == nil)
    }

    @Test
    func overrideRouteChangeIsMarkedAdaptable() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)
        let notification = Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.override.rawValue]
        )

        let event = subject.routeChangeEvent(from: notification)

        #expect(event.reason == .override)
        #expect(event.reasonDescription == "override")
        #expect(event.shouldAdapt)
    }
}

private final class MockVoiceAudioSessionClient: VoiceAudioSessionClient {
    var categoryRawValue = AVAudioSession.Category.playAndRecord.rawValue
    var modeRawValue = AVAudioSession.Mode.voiceChat.rawValue
    var sampleRate: Double = 48_000
    var ioBufferDuration: TimeInterval = 0.023
    var preferredInputDescription = "none"
    var currentRouteSnapshot = VoiceAudioRouteSnapshot(inputs: [], outputs: [])
    var availableInputSnapshots: [VoiceAudioPortSnapshot] = [
        VoiceAudioPortSnapshot(rawPortType: AVAudioSession.Port.builtInMic.rawValue, portName: "iPhone Microphone")
    ]

    private(set) var lastCategory: AVAudioSession.Category?
    private(set) var lastMode: AVAudioSession.Mode?
    private(set) var lastOptions: AVAudioSession.CategoryOptions?
    private(set) var lastPreferredIOBufferDuration: TimeInterval?
    private(set) var setActiveValues: [Bool] = []
    private(set) var lastOverride: AVAudioSession.PortOverride?
    private(set) var lastPreferredInput: VoiceAudioInputPreference?

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        lastCategory = category
        lastMode = mode
        lastOptions = options
        categoryRawValue = category.rawValue
        modeRawValue = mode.rawValue
    }

    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {
        lastPreferredIOBufferDuration = duration
    }

    func setActive(_ active: Bool) throws {
        setActiveValues.append(active)
    }

    func overrideOutputAudioPort(_ portOverride: AVAudioSession.PortOverride) throws {
        lastOverride = portOverride
    }

    func setPreferredInput(_ preference: VoiceAudioInputPreference) throws {
        lastPreferredInput = preference
        switch preference {
        case .none:
            preferredInputDescription = "none"
        case .builtInMic:
            preferredInputDescription = "\(AVAudioSession.Port.builtInMic.rawValue):iPhone Microphone"
        }
    }

    var isEchoCancelledInputAvailable: Bool = true
    private(set) var lastPrefersEchoCancelledInput: Bool?

    func setPrefersEchoCancelledInput(_ enabled: Bool) throws {
        lastPrefersEchoCancelledInput = enabled
    }
}
