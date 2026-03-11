import SwiftData
import XCTest
@testable import heard

@MainActor
final class GeminiServiceSetupTests: XCTestCase {
    // TODO: Test proactiveAudio WITHOUT LOW start sensitivity — untested combination
    //       that may give better barge-in than current config while still rejecting echo.
    //       See docs/testing/audio-calibration-testing.md for full test matrix.

    // TODO: Add a test for silenceDurationMs at 300 (faster turn-taking variant)
    //       to verify payload shape if we decide to reduce the current 500ms value.

    func testAudioSetupPayloadConfiguresVadForEchoRejection() throws {
        let service = makeService()

        let payload = service.makeSetupPayload(config: .audio())
        let setup = try XCTUnwrap(payload["setup"] as? [String: Any])
        let realtimeInputConfig = try XCTUnwrap(setup["realtimeInputConfig"] as? [String: Any])
        let aad = try XCTUnwrap(
            realtimeInputConfig["automaticActivityDetection"] as? [String: Any]
        )

        // LOW start sensitivity rejects residual echo past iOS AEC
        XCTAssertEqual(aad["startOfSpeechSensitivity"] as? String, "START_SENSITIVITY_LOW")
        // End-of-speech tuned to avoid echo decay being misread as speech
        XCTAssertEqual(aad["endOfSpeechSensitivity"] as? String, "END_SENSITIVITY_LOW")
        XCTAssertEqual(aad["prefixPaddingMs"] as? Int, 40)
        XCTAssertEqual(aad["silenceDurationMs"] as? Int, 500)
        // proactiveAudio disabled — stacked with LOW start sensitivity it suppresses barge-in
        XCTAssertNil(setup["proactivity"])
    }

    func testTextSetupPayloadDoesNotIncludeAudioOnlyRealtimeConfig() throws {
        let service = makeService()

        let payload = service.makeSetupPayload(config: .text())
        let setup = try XCTUnwrap(payload["setup"] as? [String: Any])
        let generationConfig = try XCTUnwrap(setup["generationConfig"] as? [String: Any])

        XCTAssertEqual(generationConfig["responseModalities"] as? [String], ["TEXT"])
        XCTAssertNil(setup["realtimeInputConfig"])
        XCTAssertNil(setup["proactivity"])
        XCTAssertNil(setup["outputAudioTranscription"])
        XCTAssertNil(setup["inputAudioTranscription"])
    }

    private func makeService() -> GeminiService {
        let context = HeardChefApp().sharedModelContainer.mainContext
        return GeminiService(modelContext: context)
    }
}
