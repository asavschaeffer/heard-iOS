import SwiftData
import Testing
@testable import heard

@Suite(.tags(.hosted, .configuration))
@MainActor
struct GeminiServiceSetupTests {
    struct AudioSetupExpectation: Sendable {
        let name: String
        let profile: GeminiAudioSetupProfile
        let expectedProactivity: Bool
    }

    private static let audioSetupExpectations = [
        AudioSetupExpectation(
            name: "echo rejecting default",
            profile: .echoRejectingDefault,
            expectedProactivity: false
        ),
        AudioSetupExpectation(
            name: "proactive audio without low start sensitivity",
            profile: .noLowStartSensitivityWithProactivity,
            expectedProactivity: true
        ),
        AudioSetupExpectation(
            name: "faster turn taking at 300ms silence",
            profile: .fasterTurnTaking300ms,
            expectedProactivity: false
        )
    ]

    @Test(arguments: Self.audioSetupExpectations)
    func audioSetupPayloadProfiles(expected: AudioSetupExpectation) throws {
        let service = makeService()

        let payload = service.makeSetupPayload(config: .audio(profile: expected.profile))
        let setup = try #require(payload["setup"] as? [String: Any])
        let generationConfig = try #require(setup["generationConfig"] as? [String: Any])
        let realtimeInputConfig = try #require(setup["realtimeInputConfig"] as? [String: Any])
        let aad = try #require(
            realtimeInputConfig["automaticActivityDetection"] as? [String: Any]
        )

        #expect(
            generationConfig["responseModalities"] as? [String] == ["AUDIO"],
            "Audio profile \(expected.name) should request audio responses."
        )
        #expect(aad["startOfSpeechSensitivity"] as? String == expected.profile.startOfSpeechSensitivity)
        #expect(aad["endOfSpeechSensitivity"] as? String == expected.profile.endOfSpeechSensitivity)
        #expect(aad["prefixPaddingMs"] as? Int == expected.profile.prefixPaddingMs)
        #expect(aad["silenceDurationMs"] as? Int == expected.profile.silenceDurationMs)
        #expect((setup["proactivity"] != nil) == expected.expectedProactivity)
        if expected.expectedProactivity {
            let proactivity = try #require(setup["proactivity"] as? [String: Any])
            #expect(proactivity["proactiveAudio"] as? Bool == true)
        } else {
            #expect(setup["proactivity"] == nil)
        }
        #expect(setup["outputAudioTranscription"] as? [String: Any] != nil)
        #expect(setup["inputAudioTranscription"] as? [String: Any] != nil)
    }

    @Test
    func activityHandlingAndTurnCoverageAppearInPayloadWhenSet() throws {
        let service = makeService()

        let profile = GeminiAudioSetupProfile(
            startOfSpeechSensitivity: "START_SENSITIVITY_LOW",
            endOfSpeechSensitivity: "END_SENSITIVITY_LOW",
            prefixPaddingMs: 40,
            silenceDurationMs: 500,
            includesProactivity: false,
            activityHandling: "NO_INTERRUPTION",
            turnCoverage: "TURN_INCLUDES_ALL_INPUT"
        )

        let payload = service.makeSetupPayload(config: .audio(profile: profile))
        let setup = try #require(payload["setup"] as? [String: Any])
        let realtimeInputConfig = try #require(setup["realtimeInputConfig"] as? [String: Any])

        #expect(realtimeInputConfig["activityHandling"] as? String == "NO_INTERRUPTION")
        #expect(realtimeInputConfig["turnCoverage"] as? String == "TURN_INCLUDES_ALL_INPUT")
    }

    @Test
    func activityHandlingAndTurnCoverageOmittedWhenNil() throws {
        let service = makeService()

        let payload = service.makeSetupPayload(config: .audio(profile: .echoRejectingDefault))
        let setup = try #require(payload["setup"] as? [String: Any])
        let realtimeInputConfig = try #require(setup["realtimeInputConfig"] as? [String: Any])

        #expect(realtimeInputConfig["activityHandling"] == nil)
        #expect(realtimeInputConfig["turnCoverage"] == nil)
    }

    @Test
    func textSetupPayloadDoesNotIncludeAudioOnlyRealtimeConfig() throws {
        let service = makeService()

        let payload = service.makeSetupPayload(config: .text())
        let setup = try #require(payload["setup"] as? [String: Any])
        let generationConfig = try #require(setup["generationConfig"] as? [String: Any])

        #expect(generationConfig["responseModalities"] as? [String] == ["TEXT"])
        #expect(setup["realtimeInputConfig"] == nil)
        #expect(setup["proactivity"] == nil)
        #expect(setup["outputAudioTranscription"] == nil)
        #expect(setup["inputAudioTranscription"] == nil)
    }

    @Test
    func audioPromptExtendsTextPromptForLiveCalls() {
        let service = makeService()

        let audioPrompt = service.makeSystemPrompt(for: .audio)
        let textPrompt = service.makeSystemPrompt(for: .text)

        #expect(audioPrompt != textPrompt)
        #expect(audioPrompt.starts(with: textPrompt))
        #expect(audioPrompt.count > textPrompt.count)
    }

    @Test
    func customVoiceNameAppearsInAudioPayload() throws {
        let service = makeService()

        var profile = GeminiAudioSetupProfile.echoRejectingDefault
        profile.voiceName = GeminiVoice.puck.rawValue

        let payload = service.makeSetupPayload(config: .audio(profile: profile))
        let setup = try #require(payload["setup"] as? [String: Any])
        let generationConfig = try #require(setup["generationConfig"] as? [String: Any])
        let speechConfig = try #require(generationConfig["speechConfig"] as? [String: Any])
        let voiceConfig = try #require(speechConfig["voiceConfig"] as? [String: Any])
        let prebuiltVoiceConfig = try #require(voiceConfig["prebuiltVoiceConfig"] as? [String: Any])

        #expect(prebuiltVoiceConfig["voiceName"] as? String == "Puck")
    }

    private func makeService() -> GeminiService {
        let context = HeardChefApp().sharedModelContainer.mainContext
        return GeminiService(modelContext: context)
    }
}
