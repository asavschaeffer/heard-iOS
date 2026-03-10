import XCTest
@testable import VoiceCore

@MainActor
final class VoicePlaybackEngineTests: XCTestCase {
    func testSimulatedQueueDrainClearsSpeakingState() {
        let engine = VoicePlaybackEngine()

        engine.simulateScheduledBufferForTesting()

        XCTAssertEqual(engine.enqueuedBufferCount, 1)
        XCTAssertTrue(engine.isSpeaking)

        engine.simulatePlaybackCompletionForTesting()

        XCTAssertEqual(engine.enqueuedBufferCount, 0)
        XCTAssertFalse(engine.isSpeaking)
    }

    func testStopClearsQueuedPlaybackState() {
        let engine = VoicePlaybackEngine()

        engine.simulateScheduledBufferForTesting()
        engine.stop(clearQueue: true)

        XCTAssertEqual(engine.enqueuedBufferCount, 0)
        XCTAssertFalse(engine.isSpeaking)
        XCTAssertFalse(engine.isRunning)
    }
}
