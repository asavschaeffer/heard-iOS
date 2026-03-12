import Testing
@preconcurrency import AVFoundation
@testable import VoiceCore

@Suite(.tags(.voicecore))
@MainActor
struct VoiceCaptureEngineTests {
    @Test
    func processAudioBufferEmitsPCMWhenCaptureIsAllowed() async {
        let engine = VoiceCaptureEngine()
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        engine.prepareConverterForTesting(inputFormat: inputFormat)
        engine.shouldSendAudio = { true }

        let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            channel[index] = 0.5
        }

        var receivedChunks = [Data]()
        engine.onAudioData = { data in
            receivedChunks.append(data)
        }

        engine.processAudioBufferForTesting(buffer)
        await flushMainActorTasks()

        #expect(receivedChunks.count == 1)
        #expect(receivedChunks.first?.isEmpty == false)
        #expect(engine.metrics.chunkCount == 1)
        #expect(engine.metrics.byteCount > 0)
    }

    @Test
    func repeatedSilentStopsDisableVoiceProcessingInput() {
        let engine = VoiceCaptureEngine()

        _ = engine.stop()
        _ = engine.stop()
        _ = engine.stop()

        #expect(engine.consecutiveSilentStops == 3)
        #expect(engine.useVoiceProcessingInput == false)
    }

    @Test
    func zeroChunkFallbackRequestsRestartAfterThreshold() async {
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

        var didRequestFallback = false
        engine.onVoiceProcessingFallbackRequested = {
            didRequestFallback = true
        }

        for _ in 0..<150 {
            engine.processAudioBufferForTesting(buffer)
        }
        await flushMainActorTasks()

        #expect(didRequestFallback)
        #expect(engine.useVoiceProcessingInput == false)
    }

    private func flushMainActorTasks(iterations: Int = 5) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }
}
