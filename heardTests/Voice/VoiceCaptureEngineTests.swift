import XCTest
@preconcurrency import AVFoundation
@testable import heard

@MainActor
final class VoiceCaptureEngineTests: XCTestCase {
    func testProcessAudioBufferEmitsPCMWhenCaptureIsAllowed() async {
        let engine = VoiceCaptureEngine()
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        engine.prepareConverterForTesting(inputFormat: inputFormat)
        engine.shouldSendAudio = { true }

        let expectation = expectation(description: "audio data emitted")
        engine.onAudioData = { data in
            XCTAssertFalse(data.isEmpty)
            expectation.fulfill()
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            channel[index] = 0.5
        }

        engine.processAudioBufferForTesting(buffer)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(engine.metrics.chunkCount, 1)
        XCTAssertGreaterThan(engine.metrics.byteCount, 0)
    }

    func testRepeatedSilentStopsDisableVoiceProcessingInput() {
        let engine = VoiceCaptureEngine()

        _ = engine.stop()
        _ = engine.stop()
        _ = engine.stop()

        XCTAssertEqual(engine.consecutiveSilentStops, 3)
        XCTAssertFalse(engine.useVoiceProcessingInput)
    }

    func testZeroChunkFallbackRequestsRestartAfterThreshold() async {
        let engine = VoiceCaptureEngine()
        engine.shouldSendAudio = { true }
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 32)!
        buffer.frameLength = 32

        let expectation = expectation(description: "fallback requested")
        engine.onVoiceProcessingFallbackRequested = {
            expectation.fulfill()
        }

        for _ in 0..<150 {
            engine.processAudioBufferForTesting(buffer)
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(engine.useVoiceProcessingInput)
    }
}
