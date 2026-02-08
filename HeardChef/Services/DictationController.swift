import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class DictationController: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let recognizer = SFSpeechRecognizer()
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }
        authorizationStatus = status
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func toggleDictation() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        // 1. Request speech recognition permission
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        guard authorizationStatus == .authorized else {
            print("[Dictation] Speech recognition not authorized: \(authorizationStatus.rawValue)")
            return
        }

        // 2. Request microphone permission
        let micGranted = await requestMicrophoneAccess()
        guard micGranted else {
            print("[Dictation] Microphone permission denied")
            return
        }

        guard recognizer?.isAvailable == true else {
            print("[Dictation] Speech recognizer not available")
            return
        }

        stop()
        transcript = ""

        // 3. Configure audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("[Dictation] Audio session error: \(error.localizedDescription)")
        }

        // 4. Create a fresh audio engine each time (avoids stale input node state)
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("[Dictation] No microphone input available (format: \(recordingFormat))")
            audioEngine = nil
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[Dictation] Audio engine start error: \(error)")
            stop()
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    print("[Dictation] Recognition error: \(error)")
                    self.stop()
                } else if result?.isFinal == true {
                    self.stop()
                }
            }
        }

        isRecording = true
        print("[Dictation] Started recording (\(recordingFormat.sampleRate) Hz)")
    }

    func stop() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}
