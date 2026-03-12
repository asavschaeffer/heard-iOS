import Foundation
import Combine
import AVFoundation
import Speech
import UIKit

@MainActor
final class AppWarmup: ObservableObject {

    enum Step: String, CaseIterable, Sendable {
        case audioSession = "Audio Session"
        case captureEngine = "Capture Engine"
        case cameraAuthorization = "Camera Authorization"
        case speechRecognizer = "Speech Recognizer"
        case dataDetector = "Data Detector"
        case hapticEngine = "Haptic Engine"
    }

    @Published private(set) var completedSteps: Set<Step> = []
    @Published private(set) var isFinished = false

    var progress: Double {
        Double(completedSteps.count) / Double(Step.allCases.count)
    }

    func runAll() {
        print("[Warmup] Starting all warmup tasks")

        // Audio pipeline (sequential — session must come first)
        Task {
            await WarmupWork.audioSession()
            markDone(.audioSession)

            await WarmupWork.captureEngine()
            markDone(.captureEngine)
        }

        // Camera framework
        Task {
            await WarmupWork.cameraAuthorization()
            markDone(.cameraAuthorization)
        }

        // Speech framework
        Task {
            await WarmupWork.speechRecognizer()
            markDone(.speechRecognizer)
        }

        // Data detector + haptics
        Task {
            await WarmupWork.dataDetector()
            markDone(.dataDetector)

            SharedHaptics.generator.prepare()
            markDone(.hapticEngine)
        }
    }

    private func markDone(_ step: Step) {
        completedSteps.insert(step)
        print("[Warmup] \(step.rawValue) — ready (\(self.completedSteps.count)/\(Step.allCases.count))")
        if completedSteps.count == Step.allCases.count {
            isFinished = true
            print("[Warmup] All warmup tasks complete")
        }
    }
}

// MARK: - Background Warmup Work (nonisolated)

private enum WarmupWork {

    static func audioSession() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                print("[Warmup] Audio Session — loading")
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setPreferredIOBufferDuration(0.02)
                    try session.setActive(true)
                } catch {
                    print("[Warmup] Audio Session warning: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    static func captureEngine() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                print("[Warmup] Capture Engine — loading")
                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                let inputFormat = inputNode.inputFormat(forBus: 0)

                guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                    print("[Warmup] Capture Engine: invalid input format, skipping")
                    continuation.resume()
                    return
                }

                engine.prepare()
                do {
                    try engine.start()
                    engine.stop()
                } catch {
                    print("[Warmup] Capture Engine warning: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    static func cameraAuthorization() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                print("[Warmup] Camera Authorization — loading")
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .authorized {
                    _ = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                }
                continuation.resume()
            }
        }
    }

    static func speechRecognizer() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                print("[Warmup] Speech Recognizer — loading")
                let _ = SFSpeechRecognizer()
                continuation.resume()
            }
        }
    }

    static func dataDetector() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                print("[Warmup] Data Detector — loading")
                _ = SharedDataDetector.linkDetector
                continuation.resume()
            }
        }
    }
}

// MARK: - Shared Singletons

enum SharedDataDetector {
    static let linkDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()
}

@MainActor
enum SharedHaptics {
    static let generator = UINotificationFeedbackGenerator()
}
