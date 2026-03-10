import Foundation
@preconcurrency import AVFoundation

struct VoiceCaptureMetrics: Equatable {
    var callbackCount = 0
    var chunkCount = 0
    var byteCount = 0
}

@MainActor
protocol VoiceCaptureHandling: AnyObject {
    var isRunning: Bool { get }
    var useVoiceProcessingInput: Bool { get set }
    var metrics: VoiceCaptureMetrics { get }
    var consecutiveSilentStops: Int { get }
    var onAudioLevel: ((Float) -> Void)? { get set }
    var onAudioData: ((Data) -> Void)? { get set }
    var shouldSendAudio: (() -> Bool)? { get set }
    var onVoiceProcessingFallbackRequested: (() -> Void)? { get set }

    func start()
    func stop() -> VoiceCaptureMetrics
    func processAudioBufferForTesting(_ buffer: AVAudioPCMBuffer)
    func prepareConverterForTesting(inputFormat: AVAudioFormat)
}

@MainActor
final class VoiceCaptureEngine: VoiceCaptureHandling {
    enum Constants {
        static let captureSampleRate: Double = 16_000
        static let audioLevelReportingRate: Double = 25
        static let voiceProcessingFallbackThreshold = 150
    }

    private var audioEngine: AVAudioEngine?
    private var captureConverter: AVAudioConverter?
    private var captureTargetFormat: AVAudioFormat?
    private(set) var metrics = VoiceCaptureMetrics()
    private(set) var consecutiveSilentStops = 0

    var useVoiceProcessingInput = true
    var onAudioLevel: ((Float) -> Void)?
    var onAudioData: ((Data) -> Void)?
    var shouldSendAudio: (() -> Bool)?
    var onVoiceProcessingFallbackRequested: (() -> Void)?

    var isRunning: Bool {
        audioEngine?.isRunning == true
    }

    func start() {
        if isRunning {
            VoiceDiagnostics.audio("[Audio] Capture start skipped reason=already-running")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if useVoiceProcessingInput {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                VoiceDiagnostics.audio("[Audio] Voice processing input enabled")
            } catch {
                VoiceDiagnostics.audio("[Audio] Voice processing enable failed, using fallback input path: \(error.localizedDescription)")
                useVoiceProcessingInput = false
            }
        } else {
            VoiceDiagnostics.audio("[Audio] Voice processing input disabled (fallback mode)")
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        VoiceDiagnostics.audio("[Audio] Starting capture. inputRate=\(Int(inputFormat.sampleRate))Hz channels=\(inputFormat.channelCount)")
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.captureSampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            VoiceDiagnostics.fault("[Audio] Audio conversion setup error")
            return
        }

        captureConverter = converter
        captureTargetFormat = targetFormat
        audioEngine = engine
        let bufferSize = AVAudioFrameCount(max(256.0, inputFormat.sampleRate / Constants.audioLevelReportingRate))
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            metrics = VoiceCaptureMetrics()
            VoiceDiagnostics.audio(
                "[Audio] Capture started inputRate=\(Int(inputFormat.sampleRate))Hz channels=\(inputFormat.channelCount) targetRate=\(Int(Constants.captureSampleRate))Hz"
            )
        } catch {
            VoiceDiagnostics.fault("[Audio] Audio Engine Start Error: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
            captureConverter = nil
            captureTargetFormat = nil
        }
    }

    @discardableResult
    func stop() -> VoiceCaptureMetrics {
        let finalMetrics = metrics
        if finalMetrics.chunkCount > 0 {
            consecutiveSilentStops = 0
            VoiceDiagnostics.audio(
                "[Audio] Capture stopped. callbacks=\(finalMetrics.callbackCount) chunks=\(finalMetrics.chunkCount) bytes=\(finalMetrics.byteCount)"
            )
        } else {
            consecutiveSilentStops += 1
            VoiceDiagnostics.audio("[Audio] Capture stopped with no outgoing chunks (callbacks=\(finalMetrics.callbackCount))")
            if useVoiceProcessingInput && consecutiveSilentStops >= 3 {
                VoiceDiagnostics.audio("[Audio] Switching to non-voice-processing input after repeated zero-chunk stops")
                useVoiceProcessingInput = false
            }
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        captureConverter = nil
        captureTargetFormat = nil
        Task { @MainActor [weak self] in
            self?.onAudioLevel?(0)
        }
        return finalMetrics
    }

    func processAudioBufferForTesting(_ buffer: AVAudioPCMBuffer) {
        processAudioBuffer(buffer)
    }

    func prepareConverterForTesting(inputFormat: AVAudioFormat) {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.captureSampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return
        }

        captureConverter = converter
        captureTargetFormat = targetFormat
        metrics = VoiceCaptureMetrics()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        metrics.callbackCount += 1
        if metrics.callbackCount == 1 || metrics.callbackCount % 50 == 0 {
            VoiceDiagnostics.audio("[Audio] Tap callback #\(metrics.callbackCount), frames=\(buffer.frameLength)")
        }

        if useVoiceProcessingInput,
           shouldSendAudio?() == true,
           metrics.callbackCount >= Constants.voiceProcessingFallbackThreshold,
           metrics.chunkCount == 0 {
            VoiceDiagnostics.audio("[Audio] No outgoing chunks while callbacks are firing on voice-processing path; switching to fallback input")
            useVoiceProcessingInput = false
            Task { @MainActor [weak self] in
                self?.onVoiceProcessingFallbackRequested?()
            }
            return
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        if let channelData = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for index in 0..<frameLength {
                sum += abs(channelData[index])
            }
            let average = sum / Float(frameLength)
            Task { @MainActor [weak self] in
                self?.onAudioLevel?(min(1.0, average * 10))
            }
        }

        guard shouldSendAudio?() == true else { return }
        guard let pcmData = convertCapturedBufferToPCM16(buffer), !pcmData.isEmpty else { return }

        metrics.chunkCount += 1
        metrics.byteCount += pcmData.count
        if metrics.chunkCount == 1 || metrics.chunkCount % 200 == 0 {
            VoiceDiagnostics.audio(
                "[Audio] Captured chunk #\(metrics.chunkCount), bytes=\(pcmData.count), totalBytes=\(metrics.byteCount)"
            )
        }

        Task { @MainActor [weak self] in
            self?.onAudioData?(pcmData)
        }
    }

    private func convertCapturedBufferToPCM16(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = captureConverter, let targetFormat = captureTargetFormat else { return nil }

        let sampleRateRatio = targetFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let outputFrameCapacity = AVAudioFrameCount(max(1, ceil(Double(buffer.frameLength) * sampleRateRatio)))

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }

        var error: NSError?
        var inputConsumed = false
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }

            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            if let error {
                VoiceDiagnostics.fault("[Audio] Audio conversion error: \(error.localizedDescription)")
            }
            return nil
        }

        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0,
              let channelData = convertedBuffer.int16ChannelData?[0] else {
            return nil
        }

        let byteCount = frameLength * MemoryLayout<Int16>.size
        return Data(bytes: channelData, count: byteCount)
    }
}
