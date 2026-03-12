import SwiftData
import Testing
@testable import heard

@Suite(.tags(.hosted, .configuration))
@MainActor
struct GeminiServiceSetupTests {
    // TODO: Test proactiveAudio WITHOUT LOW start sensitivity — untested combination
    //       that may give better barge-in than current config while still rejecting echo.
    //       See docs/testing/audio-calibration-testing.md for full test matrix.

    // TODO: Add a test for silenceDurationMs at 300 (faster turn-taking variant)
    //       to verify payload shape if we decide to reduce the current 500ms value.

    @Test
    func audioSetupPayloadConfiguresVadForEchoRejection() throws {
        let service = makeService()

        let payload = service.makeSetupPayload(config: .audio())
        let setup = try #require(payload["setup"] as? [String: Any])
        let realtimeInputConfig = try #require(setup["realtimeInputConfig"] as? [String: Any])
        let aad = try #require(
            realtimeInputConfig["automaticActivityDetection"] as? [String: Any]
        )

        // LOW start sensitivity rejects residual echo past iOS AEC
        #expect(aad["startOfSpeechSensitivity"] as? String == "START_SENSITIVITY_LOW")
        // End-of-speech tuned to avoid echo decay being misread as speech
        #expect(aad["endOfSpeechSensitivity"] as? String == "END_SENSITIVITY_LOW")
        #expect(aad["prefixPaddingMs"] as? Int == 40)
        #expect(aad["silenceDurationMs"] as? Int == 500)
        // proactiveAudio disabled — stacked with LOW start sensitivity it suppresses barge-in
        #expect(setup["proactivity"] == nil)
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
