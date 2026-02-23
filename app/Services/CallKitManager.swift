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
        request(transaction: transaction)
    }

    func endCall() {
        guard let callId = currentCall?.id else { return }
        let endAction = CXEndCallAction(call: callId)
        let transaction = CXTransaction(action: endAction)
        request(transaction: transaction)
    }

    func reportConnected() {
        guard let callId = currentCall?.id else { return }
        provider.reportOutgoingCall(with: callId, connectedAt: Date())
    }

    private func request(transaction: CXTransaction) {
        callController.request(transaction) { error in
            if let error {
                let details = Self.describeTransactionError(error)
                print("CallKit transaction error: \(details)")
                Task { @MainActor in
                    self.onTransactionError?(error)
                }
            } else {
                print("[CallKit] Transaction request accepted")
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
        currentCall = nil
        onStopAudio?()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        onStopAudio?()
        currentCall = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        onMuteChanged?(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        onStartAudio?()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        onStopAudio?()
    }
}
