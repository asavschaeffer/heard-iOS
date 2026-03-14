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
        case textInput = "Text Input"
        case menuSystem = "Menu System"
    }

    @Published private(set) var completedSteps: Set<Step> = []
    @Published private(set) var isFinished = false

    var completedStepCount: Int {
        completedSteps.count
    }

    var progress: Double {
        Double(completedSteps.count) / Double(Step.allCases.count)
    }

    func runAll() {
        print("[Warmup] Starting all warmup tasks")

        // Audio pipeline (sequential — session must come first)
        Task {
            await WarmupWork.audioSession()
            recordCompletion(of: .audioSession)

            await WarmupWork.captureEngine()
            recordCompletion(of: .captureEngine)
        }

        // Camera framework
        Task {
            await WarmupWork.cameraAuthorization()
            recordCompletion(of: .cameraAuthorization)
        }

        // Speech framework
        Task {
            await WarmupWork.speechRecognizer()
            recordCompletion(of: .speechRecognizer)
        }

        // Data detector + haptics
        Task {
            await WarmupWork.dataDetector()
            recordCompletion(of: .dataDetector)

            SharedHaptics.generator.prepare()
            recordCompletion(of: .hapticEngine)
        }

        // UIKit interaction stack
        Task {
            await WarmupWork.textInput()
            recordCompletion(of: .textInput)

            await WarmupWork.menuSystem()
            recordCompletion(of: .menuSystem)
        }
    }

    func recordCompletion(of step: Step) {
        let result = completedSteps.insert(step)
        guard result.inserted else { return }

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

    static func textInput() async {
        await UIInteractionWarmup.warmTextInput()
    }

    static func menuSystem() async {
        await UIInteractionWarmup.warmMenuSystem()
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
