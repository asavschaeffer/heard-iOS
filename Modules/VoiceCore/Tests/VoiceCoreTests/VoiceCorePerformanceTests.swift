import XCTest
@preconcurrency import AVFoundation
@testable import VoiceCore

@MainActor
final class VoiceCorePerformanceTests: XCTestCase {
    func testCaptureBufferProcessingPerformance() {
        let engine = VoiceCaptureEngine()
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            channel[index] = 0.5
        }
        engine.prepareConverterForTesting(inputFormat: inputFormat)
        engine.shouldSendAudio = { true }

        measure(metrics: [XCTClockMetric()]) {
            engine.processAudioBufferForTesting(buffer)
            XCTAssertGreaterThan(engine.metrics.byteCount, 0)
        }
    }

    func testPlaybackQueueDrainPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            let engine = VoicePlaybackEngine()

            for _ in 0..<250 {
                engine.simulateScheduledBufferForTesting()
            }
            for _ in 0..<250 {
                engine.simulatePlaybackCompletionForTesting()
            }

            XCTAssertEqual(engine.enqueuedBufferCount, 0)
            XCTAssertFalse(engine.isSpeaking)
        }
    }
}
