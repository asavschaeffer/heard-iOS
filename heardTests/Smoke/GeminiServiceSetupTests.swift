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

    private func makeService() -> GeminiService {
        let context = HeardChefApp().sharedModelContainer.mainContext
        return GeminiService(modelContext: context)
    }
}
