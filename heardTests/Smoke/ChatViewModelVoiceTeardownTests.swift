import Foundation
import SwiftData
import Testing
import VoiceCore
@testable import heard

@Suite(.serialized, .tags(.hosted, .smoke))
@MainActor
struct ChatViewModelVoiceTeardownTests {
    @Test
    func intentionalStopRequestsDisconnectOnceAndWaitsForDelegateCompletion() {
        let modelContext = HeardChefApp().sharedModelContainer.mainContext
        let service = MockGeminiService(modelContext: modelContext)
        service.stubHasActiveSocketSession = true
        let coordinator = MockVoiceCoordinator()
        let viewModel = ChatViewModel(
            geminiServiceFactory: { _ in service },
            voiceCoordinator: coordinator,
            shouldBootstrapThreadOnModelContext: false
        )
        viewModel.setModelContext(modelContext)
        viewModel.callState.isPresented = true
        viewModel.connectionState = .connected

        viewModel.stopVoiceSession()
        viewModel.stopVoiceSession()

        #expect(service.disconnectReasons == ["stopVoiceSession"])
        #expect(coordinator.stopCallCount == 1)
        #expect(coordinator.transportDisconnectCount == 0)
        #expect(viewModel.connectionState == .connected)
        #expect(viewModel.isStoppingCall)
        #expect(viewModel.hasScheduledReconnect == false)

        viewModel.geminiServiceDidDisconnect(service)

        #expect(viewModel.connectionState == .disconnected)
        #expect(viewModel.isStoppingCall == false)
        #expect(viewModel.hasScheduledReconnect == false)
        #expect(coordinator.transportDisconnectCount == 1)
        #expect(coordinator.transportDisconnectAutoReconnects == [false])
    }

    @Test
    func stopFinalizesLocallyWhenNoSocketSessionExists() {
        let modelContext = HeardChefApp().sharedModelContainer.mainContext
        let service = MockGeminiService(modelContext: modelContext)
        service.stubHasActiveSocketSession = false
        let coordinator = MockVoiceCoordinator()
        let viewModel = ChatViewModel(
            geminiServiceFactory: { _ in service },
            voiceCoordinator: coordinator,
            shouldBootstrapThreadOnModelContext: false
        )
        viewModel.setModelContext(modelContext)
        viewModel.callState.isPresented = true
        viewModel.connectionState = .connected

        viewModel.stopVoiceSession()

        #expect(service.disconnectReasons == ["stopVoiceSession"])
        #expect(coordinator.stopCallCount == 1)
        #expect(viewModel.connectionState == .disconnected)
        #expect(viewModel.isStoppingCall == false)
        #expect(viewModel.hasScheduledReconnect == false)
        #expect(coordinator.transportDisconnectCount == 1)
        #expect(coordinator.transportDisconnectAutoReconnects == [false])
    }

    @Test
    func unexpectedDisconnectStillSchedulesReconnectDuringActiveCall() {
        let modelContext = HeardChefApp().sharedModelContainer.mainContext
        let service = MockGeminiService(modelContext: modelContext)
        let coordinator = MockVoiceCoordinator()
        let viewModel = ChatViewModel(
            geminiServiceFactory: { _ in service },
            voiceCoordinator: coordinator,
            shouldBootstrapThreadOnModelContext: false
        )
        viewModel.setModelContext(modelContext)
        viewModel.callState.isPresented = true
        viewModel.connectionState = .connected

        viewModel.geminiServiceDidDisconnect(service)

        #expect(viewModel.connectionState == .disconnected)
        #expect(viewModel.isStoppingCall == false)
        #expect(viewModel.hasScheduledReconnect)
        #expect(coordinator.transportDisconnectCount == 1)
        #expect(coordinator.transportDisconnectAutoReconnects == [true])
    }
}

@MainActor
private final class MockGeminiService: GeminiService {
    var stubHasActiveSocketSession = false
    private(set) var disconnectReasons: [String] = []

    override var hasActiveSocketSession: Bool {
        stubHasActiveSocketSession
    }

    override func disconnect(reason: String = "manual") {
        disconnectReasons.append(reason)
        stubHasActiveSocketSession = false
    }
}

@MainActor
private final class MockVoiceCoordinator: ChatVoiceCoordinating {
    weak var delegate: VoiceCallCoordinatorDelegate?
    var onCapturedAudio: ((Data) -> Void)?
    var onCallKitStartRequested: (() -> Void)?
    var onCallKitTransactionAccepted: (() -> Void)?
    var onCallKitPerformStart: (() -> Void)?
    var onCallKitActivated: (() -> Void)?
    var onPlaybackStarted: (() -> Void)?

    private(set) var stopCallCount = 0
    private(set) var transportDisconnectCount = 0
    private(set) var transportDisconnectAutoReconnects: [Bool] = []

    func prewarmPlayback() {}
    func transportWillConnect() {}
    func startCall() {}

    func stopCall() {
        stopCallCount += 1
    }

    func toggleMute() {}
    func toggleSpeaker() {}
    func transportDidConnect() {}

    func transportDidDisconnect(autoReconnect: Bool) {
        transportDisconnectCount += 1
        transportDisconnectAutoReconnects.append(autoReconnect)
    }

    func transportDidFail(message: String) {
        _ = message
    }

    func transportDidReceiveAudio(_ data: Data) {
        _ = data
    }
}
