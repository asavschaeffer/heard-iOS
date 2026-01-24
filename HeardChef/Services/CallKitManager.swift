import Foundation
import CallKit
import AVFoundation

@MainActor
final class CallKitManager: NSObject {
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

    init(appName: String) {
        let config = CXProviderConfiguration(localizedName: appName)
        config.supportsVideo = false
        config.supportedHandleTypes = [.generic]
        config.maximumCallsPerCallGroup = 1
        config.includesCallsInRecents = true
        config.supportsHolding = true
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
        provider.reportOutgoingCall(with: callId, startedConnectingAt: Date())
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
                print("CallKit transaction error: \(error)")
            }
        }
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
