import Foundation
import SwiftUI
import SwiftData
import AVFoundation

@MainActor
class VoiceViewModel: ObservableObject {

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Published Properties

    @Published var connectionState: ConnectionState = .disconnected
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var audioLevel: Float = 0.0
    @Published var alwaysListening = false
    @Published var transcriptEntries: [TranscriptEntry] = []
    @Published var currentTranscript: String?

    // MARK: - Private Properties

    private var geminiService: GeminiService?
    private var modelContext: ModelContext?
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    // MARK: - Model Context

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.geminiService = GeminiService(modelContext: context)
        self.geminiService?.delegate = self
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Connection

    func connect() {
        guard connectionState != .connecting else { return }

        connectionState = .connecting
        geminiService?.connect()
    }

    func disconnect() {
        stopListening()
        geminiService?.disconnect()
        connectionState = .disconnected
    }

    // MARK: - Listening

    func startListening() {
        guard case .connected = connectionState else { return }
        guard !isListening else { return }

        isListening = true
        startAudioCapture()
    }

    func stopListening() {
        guard isListening else { return }

        isListening = false
        stopAudioCapture()

        if let transcript = currentTranscript, !transcript.isEmpty {
            addTranscriptEntry(text: transcript, isUser: true)
            currentTranscript = nil
        }
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Install tap for audio data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
            isListening = false
        }
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioLevel = 0
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate audio level for waveform visualization
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        let average = sum / Float(frameLength)

        Task { @MainActor in
            self.audioLevel = min(1.0, average * 10)
        }

        // Convert to PCM 16-bit for Gemini
        let pcmData = convertToPCM16(buffer: buffer)
        geminiService?.sendAudio(data: pcmData)
    }

    private func convertToPCM16(buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.floatChannelData?[0] else {
            return Data()
        }

        let frameLength = Int(buffer.frameLength)
        var pcmData = Data(capacity: frameLength * 2)

        for i in 0..<frameLength {
            let sample = Int16(max(-1, min(1, channelData[i])) * Float(Int16.max))
            withUnsafeBytes(of: sample.littleEndian) { bytes in
                pcmData.append(contentsOf: bytes)
            }
        }

        return pcmData
    }

    // MARK: - Audio Playback

    private func playAudio(data: Data) {
        // Convert PCM16 data to audio buffer and play
        guard !data.isEmpty else { return }

        isSpeaking = true

        // In a full implementation, this would convert the PCM data
        // back to an audio buffer and play it through AVAudioPlayerNode
        // For now, we'll simulate playback duration

        let estimatedDuration = Double(data.count) / (16000 * 2) // 16kHz, 16-bit
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) { [weak self] in
            self?.isSpeaking = false
            if self?.alwaysListening == true {
                self?.startListening()
            }
        }
    }

    // MARK: - Transcript

    private func addTranscriptEntry(text: String, isUser: Bool) {
        let entry = TranscriptEntry(text: text, isUser: isUser, timestamp: Date())
        transcriptEntries.append(entry)

        // Keep only last 20 entries
        if transcriptEntries.count > 20 {
            transcriptEntries.removeFirst()
        }
    }
}

// MARK: - GeminiServiceDelegate

extension VoiceViewModel: GeminiServiceDelegate {
    func geminiServiceDidConnect(_ service: GeminiService) {
        connectionState = .connected
    }

    func geminiServiceDidDisconnect(_ service: GeminiService) {
        connectionState = .disconnected
        isListening = false
        isSpeaking = false
    }

    func geminiService(_ service: GeminiService, didReceiveError error: Error) {
        connectionState = .error(error.localizedDescription)
        isListening = false
        isSpeaking = false
    }

    func geminiService(_ service: GeminiService, didReceiveTranscript transcript: String, isFinal: Bool) {
        if isFinal {
            currentTranscript = nil
            // User's final transcript is added when we get the AI response
        } else {
            currentTranscript = transcript
        }
    }

    func geminiService(_ service: GeminiService, didReceiveResponse text: String) {
        addTranscriptEntry(text: text, isUser: false)
    }

    func geminiService(_ service: GeminiService, didReceiveAudio data: Data) {
        if isListening {
            stopListening()
        }
        playAudio(data: data)
    }

    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: String) {
        // Optionally show function call results in transcript
        // For now, we'll let the AI's response summarize what happened
    }
}
