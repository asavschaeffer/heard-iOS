import Testing
@testable import VoiceCore

@Suite(.tags(.voicecore))
@MainActor
struct VoicePlaybackEngineTests {
    @Test
    func simulatedQueueDrainClearsSpeakingState() {
        let engine = VoicePlaybackEngine()

        engine.simulateScheduledBufferForTesting()

        #expect(engine.enqueuedBufferCount == 1)
        #expect(engine.isSpeaking)

        engine.simulatePlaybackCompletionForTesting()

        #expect(engine.enqueuedBufferCount == 0)
        #expect(engine.isSpeaking == false)
    }

    @Test
    func stopClearsQueuedPlaybackState() {
        let engine = VoicePlaybackEngine()

        engine.simulateScheduledBufferForTesting()
        engine.stop(clearQueue: true)

        #expect(engine.enqueuedBufferCount == 0)
        #expect(engine.isSpeaking == false)
        #expect(engine.isRunning == false)
    }
}
