import XCTest
@preconcurrency import AVFoundation
@testable import heard

@MainActor
final class VoiceAudioSessionControllerTests: XCTestCase {
    func testConfigureActiveCallKitSessionForSpeakerOverridesSpeakerAndClearsPreferredInput() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureActiveCallKitSession(preferSpeaker: true)

        XCTAssertEqual(session.lastCategory, .playAndRecord)
        XCTAssertEqual(session.lastMode, .voiceChat)
        XCTAssertEqual(session.lastOverride, .speaker)
        XCTAssertEqual(session.lastPreferredInput, VoiceAudioInputPreference.none)
    }

    func testConfigureActiveCallKitSessionForReceiverPrefersBuiltInMic() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureActiveCallKitSession(preferSpeaker: false)

        XCTAssertEqual(session.lastOverride, AVAudioSession.PortOverride.none)
        XCTAssertEqual(session.lastPreferredInput, .builtInMic)
    }

    func testConfigureNonCallKitSessionForReceiverAvoidsDefaultToSpeaker() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)

        subject.configureNonCallKitSession(preferSpeaker: false)

        XCTAssertEqual(session.lastCategory, .playAndRecord)
        XCTAssertEqual(session.lastMode, .voiceChat)
        XCTAssertFalse(session.lastOptions?.contains(.defaultToSpeaker) ?? true)
        XCTAssertEqual(session.lastPreferredInput, .builtInMic)
    }

    func testOverrideRouteChangeIsMarkedAdaptable() {
        let session = MockVoiceAudioSessionClient()
        let subject = VoiceAudioSessionController(sessionClient: session)
        let notification = Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.override.rawValue]
        )

        let event = subject.routeChangeEvent(from: notification)

        XCTAssertEqual(event.reason, .override)
        XCTAssertEqual(event.reasonDescription, "override")
        XCTAssertTrue(event.shouldAdapt)
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
}
