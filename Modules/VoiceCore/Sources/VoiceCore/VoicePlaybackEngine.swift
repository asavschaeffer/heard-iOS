import Foundation
@preconcurrency import AVFoundation

@MainActor
protocol VoicePlaybackHandling: AnyObject {
    var isRunning: Bool { get }
    var isSpeaking: Bool { get }
    var enqueuedBufferCount: Int { get }
    var onSpeakingChanged: ((Bool) -> Void)? { get set }
    var onRunningChanged: ((Bool) -> Void)? { get set }

    func play(_ data: Data)
    func prepareIfNeeded()
    func stop(clearQueue: Bool)
    func resetIdleGraphForRouteChange(reason: String)
    func simulateScheduledBufferForTesting()
    func simulatePlaybackCompletionForTesting()
}

@MainActor
final class VoicePlaybackEngine: VoicePlaybackHandling {
    enum Constants {
        static let playbackSampleRate: Double = 24_000
    }

    private var playbackEngine: AVAudioEngine?
    private var playbackNode: AVAudioPlayerNode?
    private var playbackInputFormat: AVAudioFormat?
    private var playbackConverter: AVAudioConverter?
    private var playbackFormat: AVAudioFormat?
    private(set) var enqueuedBufferCount = 0

    var onSpeakingChanged: ((Bool) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?

    var isRunning: Bool {
        playbackEngine?.isRunning == true
    }

    var isSpeaking: Bool {
        playbackNode?.isPlaying == true || enqueuedBufferCount > 0
    }

    func play(_ data: Data) {
        guard !data.isEmpty else { return }
        prepareIfNeeded()
        guard let buffer = makePCMBuffer(from: data) else { return }

        let engineWasRunning = playbackEngine?.isRunning == true
        if let engine = playbackEngine, !engine.isRunning {
            do {
                try engine.start()
                VoiceDiagnostics.audio("[Audio] Playback engine restarted bufferBytes=\(data.count)")
                onRunningChanged?(true)
            } catch {
                VoiceDiagnostics.fault("[Audio] Audio Playback restart error: \(error.localizedDescription)")
                return
            }
        }

        let shouldResetPlayer = !engineWasRunning || enqueuedBufferCount == 0
        if shouldResetPlayer {
            playbackNode?.stop()
        }

        if shouldResetPlayer || playbackNode?.isPlaying != true {
            playbackNode?.play()
            VoiceDiagnostics.audio("[Audio] Playback node started bufferBytes=\(data.count) reset=\(shouldResetPlayer)")
        }

        incrementPlaybackBufferCount()
        playbackNode?.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.decrementPlaybackBufferCount()
            }
        }
    }

    func prepareIfNeeded() {
        if playbackEngine != nil { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.playbackSampleRate,
            channels: 1,
            interleaved: false
        ),
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: inputFormat.sampleRate,
            channels: inputFormat.channelCount
        ),
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            VoiceDiagnostics.fault("[Audio] Audio Playback format setup error")
            return
        }

        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

        do {
            try engine.start()
        } catch {
            VoiceDiagnostics.fault("[Audio] Audio Playback Engine Error: \(error.localizedDescription)")
            return
        }

        playbackEngine = engine
        playbackNode = player
        playbackInputFormat = inputFormat
        playbackConverter = converter
        playbackFormat = outputFormat
        onRunningChanged?(true)
    }

    func stop(clearQueue: Bool = true) {
        _ = clearQueue
        enqueuedBufferCount = 0
        onSpeakingChanged?(false)
        playbackNode?.stop()
        playbackEngine?.stop()
        playbackNode = nil
        playbackEngine = nil
        playbackInputFormat = nil
        playbackConverter = nil
        playbackFormat = nil
        onRunningChanged?(false)
    }

    func resetIdleGraphForRouteChange(reason: String) {
        guard playbackEngine != nil || playbackNode != nil else { return }
        guard enqueuedBufferCount == 0 else {
            VoiceDiagnostics.audio("[Audio] Playback graph reset deferred reason=\(reason) enqueuedBuffers=\(enqueuedBufferCount)")
            return
        }
        VoiceDiagnostics.audio("[Audio] Resetting idle playback graph reason=\(reason)")
        stop(clearQueue: false)
    }

    func simulateScheduledBufferForTesting() {
        incrementPlaybackBufferCount()
    }

    func simulatePlaybackCompletionForTesting() {
        decrementPlaybackBufferCount()
    }

    private func makePCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard let inputFormat = playbackInputFormat,
              let outputFormat = playbackFormat,
              let converter = playbackConverter else { return nil }

        let bytesPerFrame = Int(inputFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }

        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return nil
        }

        inputBuffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Int16.self).baseAddress,
                  let destination = inputBuffer.int16ChannelData?[0] else {
                return
            }
            destination.update(from: source, count: Int(frameCount))
        }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return nil
        }

        do {
            try converter.convert(to: outputBuffer, from: inputBuffer)
            return outputBuffer.frameLength > 0 ? outputBuffer : nil
        } catch {
            VoiceDiagnostics.fault("[Audio] Audio Playback conversion error: \(error.localizedDescription)")
            return nil
        }
    }

    private func incrementPlaybackBufferCount() {
        enqueuedBufferCount += 1
        if enqueuedBufferCount == 1 {
            onSpeakingChanged?(true)
        }
    }

    private func decrementPlaybackBufferCount() {
        enqueuedBufferCount = max(0, enqueuedBufferCount - 1)
        if enqueuedBufferCount == 0 {
            playbackNode?.stop()
            onSpeakingChanged?(false)
            VoiceDiagnostics.audio("[Audio] Playback queue drained")
        }
    }
}
