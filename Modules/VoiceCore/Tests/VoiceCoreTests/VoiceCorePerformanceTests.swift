import XCTest
@preconcurrency import AVFoundation
@testable import VoiceCore

@MainActor
final class VoiceCorePerformanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoiceDiagnostics.setVerboseLoggingEnabled(false)
    }

    override func tearDown() {
        VoiceDiagnostics.setVerboseLoggingEnabled(true)
        super.tearDown()
    }

    func testCaptureBufferProcessingPerformance() {
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

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(metrics: [XCTClockMetric()], options: options) {
            let engine = VoiceCaptureEngine()
            engine.prepareConverterForTesting(inputFormat: inputFormat)
            engine.shouldSendAudio = { true }

            startMeasuring()
            engine.processAudioBufferForTesting(buffer)
            stopMeasuring()

            XCTAssertGreaterThan(engine.metrics.byteCount, 0)
        }
    }

    func testPlaybackQueueDrainPerformance() {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(metrics: [XCTClockMetric()], options: options) {
            let engine = VoicePlaybackEngine()

            for _ in 0..<250 {
                engine.simulateScheduledBufferForTesting()
            }

            startMeasuring()
            for _ in 0..<250 {
                engine.simulatePlaybackCompletionForTesting()
            }
            stopMeasuring()

            XCTAssertEqual(engine.enqueuedBufferCount, 0)
            XCTAssertFalse(engine.isSpeaking)
        }
    }
}
