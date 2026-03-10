import Foundation
@preconcurrency import AVFoundation

struct VoiceAudioPortSnapshot: Equatable {
    let rawPortType: String
    let portName: String

    var description: String {
        "\(rawPortType):\(portName)"
    }
}

struct VoiceAudioRouteSnapshot: Equatable {
    let inputs: [VoiceAudioPortSnapshot]
    let outputs: [VoiceAudioPortSnapshot]
}

struct VoiceAudioSessionSnapshot: Equatable {
    let categoryRawValue: String
    let modeRawValue: String
    let sampleRate: Double
    let ioBufferDuration: TimeInterval
    let preferredInputDescription: String
    let currentRoute: VoiceAudioRouteSnapshot
    let availableInputs: [VoiceAudioPortSnapshot]
}

struct VoiceRouteChangeEvent: Equatable {
    let reason: AVAudioSession.RouteChangeReason
    let reasonDescription: String
    let previousRouteDescription: String
    let shouldAdapt: Bool
}

struct VoiceInterruptionEvent: Equatable {
    let type: AVAudioSession.InterruptionType
    let typeDescription: String
    let options: AVAudioSession.InterruptionOptions
    let optionsDescription: String

    var shouldResume: Bool {
        options.contains(.shouldResume)
    }
}

enum VoiceAudioInputPreference: Equatable {
    case none
    case builtInMic
}

protocol VoiceAudioSessionClient: AnyObject {
    var categoryRawValue: String { get }
    var modeRawValue: String { get }
    var sampleRate: Double { get }
    var ioBufferDuration: TimeInterval { get }
    var preferredInputDescription: String { get }
    var currentRouteSnapshot: VoiceAudioRouteSnapshot { get }
    var availableInputSnapshots: [VoiceAudioPortSnapshot] { get }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws
    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws
    func setActive(_ active: Bool) throws
    func overrideOutputAudioPort(_ portOverride: AVAudioSession.PortOverride) throws
    func setPreferredInput(_ preference: VoiceAudioInputPreference) throws
}

final class SystemVoiceAudioSessionClient: VoiceAudioSessionClient {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    var categoryRawValue: String { session.category.rawValue }
    var modeRawValue: String { session.mode.rawValue }
    var sampleRate: Double { session.sampleRate }
    var ioBufferDuration: TimeInterval { session.ioBufferDuration }
    var preferredInputDescription: String {
        session.preferredInput.map { "\($0.portType.rawValue):\($0.portName)" } ?? "none"
    }
    var currentRouteSnapshot: VoiceAudioRouteSnapshot {
        Self.routeSnapshot(from: session.currentRoute)
    }
    var availableInputSnapshots: [VoiceAudioPortSnapshot] {
        Self.portSnapshots(from: session.availableInputs ?? [])
    }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        try session.setCategory(category, mode: mode, options: options)
    }

    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {
        try session.setPreferredIOBufferDuration(duration)
    }

    func setActive(_ active: Bool) throws {
        try session.setActive(active)
    }

    func overrideOutputAudioPort(_ portOverride: AVAudioSession.PortOverride) throws {
        try session.overrideOutputAudioPort(portOverride)
    }

    func setPreferredInput(_ preference: VoiceAudioInputPreference) throws {
        switch preference {
        case .none:
            try session.setPreferredInput(nil)
        case .builtInMic:
            let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic })
            try session.setPreferredInput(builtInMic)
        }
    }

    static func routeSnapshot(from route: AVAudioSessionRouteDescription) -> VoiceAudioRouteSnapshot {
        VoiceAudioRouteSnapshot(
            inputs: portSnapshots(from: route.inputs),
            outputs: portSnapshots(from: route.outputs)
        )
    }

    static func portSnapshots(from ports: [AVAudioSessionPortDescription]) -> [VoiceAudioPortSnapshot] {
        ports.map { VoiceAudioPortSnapshot(rawPortType: $0.portType.rawValue, portName: $0.portName) }
    }
}

@MainActor
protocol VoiceAudioSessionControlling: AnyObject {
    func configureNonCallKitSession(preferSpeaker: Bool)
    func configureActiveCallKitSession(preferSpeaker: Bool?)
    func applyOutputOverride(preferSpeaker: Bool) throws
    func syncSpeakerPreference() -> Bool
    func currentRouteHasOutputs() -> Bool
    func sessionSnapshot() -> VoiceAudioSessionSnapshot
    func routeChangeEvent(from notification: Notification) -> VoiceRouteChangeEvent
    func interruptionEvent(from notification: Notification) -> VoiceInterruptionEvent?
    func describe(route: VoiceAudioRouteSnapshot?) -> String
}

@MainActor
final class VoiceAudioSessionController: VoiceAudioSessionControlling {
    private let sessionClient: VoiceAudioSessionClient

    init(sessionClient: VoiceAudioSessionClient? = nil) {
        self.sessionClient = sessionClient ?? SystemVoiceAudioSessionClient()
    }

    func configureNonCallKitSession(preferSpeaker: Bool) {
        do {
            let options: AVAudioSession.CategoryOptions = preferSpeaker
                ? [.defaultToSpeaker, .allowBluetoothHFP]
                : [.allowBluetoothHFP]
            try sessionClient.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try sessionClient.setPreferredIOBufferDuration(0.02)
            try sessionClient.setActive(true)
            if !preferSpeaker {
                try sessionClient.setPreferredInput(.builtInMic)
            }
        } catch {
            VoiceDiagnostics.fault("[Audio] Session configuration failed error=\(error.localizedDescription)")
        }
    }

    func configureActiveCallKitSession(preferSpeaker: Bool?) {
        do {
            try sessionClient.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])

            if let preferSpeaker {
                try sessionClient.setPreferredInput(.none)
                try sessionClient.overrideOutputAudioPort(preferSpeaker ? .speaker : .none)
                if !preferSpeaker {
                    try sessionClient.setPreferredInput(.builtInMic)
                }
            }
        } catch {
            VoiceDiagnostics.fault("[Audio] CallKit session configuration failed error=\(error.localizedDescription)")
        }
    }

    func applyOutputOverride(preferSpeaker: Bool) throws {
        if preferSpeaker {
            try sessionClient.setPreferredInput(.none)
            try sessionClient.overrideOutputAudioPort(.speaker)
            return
        }

        try sessionClient.overrideOutputAudioPort(.none)
        try sessionClient.setPreferredInput(.builtInMic)
    }

    func syncSpeakerPreference() -> Bool {
        sessionClient.currentRouteSnapshot.outputs.contains(where: { $0.rawPortType == AVAudioSession.Port.builtInSpeaker.rawValue })
    }

    func currentRouteHasOutputs() -> Bool {
        !sessionClient.currentRouteSnapshot.outputs.isEmpty
    }

    func sessionSnapshot() -> VoiceAudioSessionSnapshot {
        VoiceAudioSessionSnapshot(
            categoryRawValue: sessionClient.categoryRawValue,
            modeRawValue: sessionClient.modeRawValue,
            sampleRate: sessionClient.sampleRate,
            ioBufferDuration: sessionClient.ioBufferDuration,
            preferredInputDescription: sessionClient.preferredInputDescription,
            currentRoute: sessionClient.currentRouteSnapshot,
            availableInputs: sessionClient.availableInputSnapshots
        )
    }

    func routeChangeEvent(from notification: Notification) -> VoiceRouteChangeEvent {
        let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) ?? .unknown
        let reasonDescription = describe(reason: reason, rawValue: reasonValue)
        let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        let previousRouteDescription = describe(route: previousRoute.map(SystemVoiceAudioSessionClient.routeSnapshot(from:)))
        let shouldAdapt: Bool
        switch reason {
        case .override, .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            shouldAdapt = true
        default:
            shouldAdapt = false
        }

        return VoiceRouteChangeEvent(
            reason: reason,
            reasonDescription: reasonDescription,
            previousRouteDescription: previousRouteDescription,
            shouldAdapt: shouldAdapt
        )
    }

    func interruptionEvent(from notification: Notification) -> VoiceInterruptionEvent? {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return nil
        }

        let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
        return VoiceInterruptionEvent(
            type: type,
            typeDescription: describe(interruptionType: type),
            options: options,
            optionsDescription: describe(interruptionOptions: options)
        )
    }

    func describe(route: VoiceAudioRouteSnapshot?) -> String {
        guard let route else { return "inputs=[] outputs=[]" }
        let inputs = describe(ports: route.inputs)
        let outputs = describe(ports: route.outputs)
        return "inputs=\(inputs) outputs=\(outputs)"
    }

    private func describe(ports: [VoiceAudioPortSnapshot]) -> String {
        guard !ports.isEmpty else { return "[]" }
        return "[\(ports.map(\.description).joined(separator: ", "))]"
    }

    private func describe(reason: AVAudioSession.RouteChangeReason, rawValue: UInt) -> String {
        switch reason {
        case .newDeviceAvailable:
            return "newDeviceAvailable"
        case .oldDeviceUnavailable:
            return "oldDeviceUnavailable"
        case .categoryChange:
            return "categoryChange"
        case .override:
            return "override"
        case .wakeFromSleep:
            return "wakeFromSleep"
        case .noSuitableRouteForCategory:
            return "noSuitableRouteForCategory"
        case .routeConfigurationChange:
            return "routeConfigurationChange"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unhandled(\(rawValue))"
        }
    }

    private func describe(interruptionType: AVAudioSession.InterruptionType) -> String {
        switch interruptionType {
        case .began:
            return "began"
        case .ended:
            return "ended"
        @unknown default:
            return "unknown"
        }
    }

    private func describe(interruptionOptions: AVAudioSession.InterruptionOptions) -> String {
        guard !interruptionOptions.isEmpty else { return "[]" }
        var values: [String] = []
        if interruptionOptions.contains(.shouldResume) {
            values.append("shouldResume")
        }
        return "[\(values.joined(separator: ", "))]"
    }
}
