import Foundation
import CallKit
import AVFoundation

@MainActor
final class CallKitManager: NSObject {
    enum TransactionErrorKind: String {
        case unentitled
        case unknownCallProvider
        case invalidAction
        case callUUIDAlreadyExists
        case maximumCallGroupsReached
        case callIsProtected
        case other
    }

    struct CallKitCall {
        let id: UUID
        let displayName: String
    }

    private let provider: CXProvider
    private let callController = CXCallController()
    private(set) var currentCall: CallKitCall?

    var onStartAudio: (() -> Void)?
    var onStopAudio: (() -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onTransactionError: ((Error) -> Void)?

    private func logCallKitEvent(_ event: String, audioSession: AVAudioSession? = nil, extra: String = "") {
        let session = audioSession ?? AVAudioSession.sharedInstance()
        let currentCallID = currentCall?.id.uuidString ?? "none"
        let currentCallName = currentCall?.displayName ?? "none"
        let routeInputs = session.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let routeOutputs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let availableInputs = (session.availableInputs ?? []).map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let prefix = extra.isEmpty ? "" : " \(extra)"
        VoiceDiagnostics.callKit(
            "[CallKit] \(event)\(prefix) | callID=\(currentCallID) displayName=\(currentCallName) category=\(session.category.rawValue) mode=\(session.mode.rawValue) sampleRate=\(Int(session.sampleRate))Hz inputs=[\(routeInputs)] outputs=[\(routeOutputs)] availableInputs=[\(availableInputs)]"
        )
    }

    init(appName: String) {
        _ = appName
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.supportedHandleTypes = [.generic]
        config.maximumCallsPerCallGroup = 1
        config.includesCallsInRecents = true
        config.ringtoneSound = nil

        self.provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    func startCall(displayName: String) {
        let callId = UUID()
        let handle = CXHandle(type: .generic, value: displayName)
        let startAction = CXStartCallAction(call: callId, handle: handle)
        let transaction = CXTransaction(action: startAction)
        currentCall = CallKitCall(id: callId, displayName: displayName)
        logCallKitEvent("startCall requested", extra: "target=\(displayName)")
        request(transaction: transaction)
    }

    func endCall() {
        guard let callId = currentCall?.id else { return }
        let endAction = CXEndCallAction(call: callId)
        let transaction = CXTransaction(action: endAction)
        logCallKitEvent("endCall requested")
        request(transaction: transaction)
    }

    func reportConnected() {
        guard let callId = currentCall?.id else { return }
        logCallKitEvent("reportConnected")
        provider.reportOutgoingCall(with: callId, connectedAt: Date())
    }

    private func request(transaction: CXTransaction) {
        callController.request(transaction) { error in
            if let error {
                let details = Self.describeTransactionError(error)
                Task { @MainActor in
                    self.logCallKitEvent("transaction request failed", extra: details)
                    self.onTransactionError?(error)
                }
            } else {
                Task { @MainActor in
                    self.logCallKitEvent("transaction request accepted")
                }
            }
        }
    }

    nonisolated static func classifyTransactionError(_ error: Error) -> TransactionErrorKind {
        let nsError = error as NSError
        guard nsError.domain == CXErrorDomainRequestTransaction else { return .other }

        switch nsError.code {
        case 1:
            return .unentitled
        case 2:
            return .unknownCallProvider
        case 6:
            return .invalidAction
        case 5:
            return .callUUIDAlreadyExists
        case 7:
            return .maximumCallGroupsReached
        case 8:
            return .callIsProtected
        default:
            return .other
        }
    }

    nonisolated static func shouldDisableCallKitAfterError(_ error: Error) -> Bool {
        switch classifyTransactionError(error) {
        case .unentitled, .unknownCallProvider:
            return true
        case .invalidAction, .callUUIDAlreadyExists, .maximumCallGroupsReached, .callIsProtected, .other:
            return false
        }
    }

    nonisolated static func describeTransactionError(_ error: Error) -> String {
        let nsError = error as NSError
        let kind = classifyTransactionError(error).rawValue
        return "domain=\(nsError.domain) code=\(nsError.code) kind=\(kind) message=\(nsError.localizedDescription)"
    }
}

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        logCallKitEvent("providerDidReset", extra: "phase=before-stop")
        currentCall = nil
        onStopAudio?()
        logCallKitEvent("providerDidReset", extra: "phase=after-stop")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        logCallKitEvent("provider perform start", extra: "actionCallID=\(action.callUUID.uuidString)")
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        logCallKitEvent("provider perform end", extra: "actionCallID=\(action.callUUID.uuidString) phase=before-stop")
        onStopAudio?()
        currentCall = nil
        action.fulfill()
        logCallKitEvent("provider perform end", extra: "actionCallID=\(action.callUUID.uuidString) phase=after-stop")
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        logCallKitEvent("provider perform mute", extra: "isMuted=\(action.isMuted)")
        onMuteChanged?(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        logCallKitEvent("provider didActivate", audioSession: audioSession)
        onStartAudio?()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        logCallKitEvent("provider didDeactivate", audioSession: audioSession)
        onStopAudio?()
    }
}
