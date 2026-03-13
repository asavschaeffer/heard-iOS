import Foundation
import SwiftData
import Testing
@testable import heard

@Suite(.serialized, .tags(.hosted, .smoke))
@MainActor
struct GeminiServiceDisconnectTests {
    @Test
    func receiveFailureIsIgnoredAfterIntentionalDisconnect() {
        let service = makeService()
        let delegate = MockGeminiDelegate()
        service.delegate = delegate

        service.disconnect(reason: "test-hangup")
        service.handleReceiveResult(.failure(MockSocketError()))

        #expect(delegate.errors.isEmpty)
    }

    @Test
    func receiveFailureStillSurfacesWhenConnectionDropsUnexpectedly() {
        let service = makeService()
        let delegate = MockGeminiDelegate()
        service.delegate = delegate

        service.handleReceiveResult(.failure(MockSocketError()))

        #expect(delegate.errors.count == 1)
    }

    private func makeService() -> GeminiService {
        let context = HeardChefApp().sharedModelContainer.mainContext
        return GeminiService(modelContext: context)
    }
}

@MainActor
private final class MockGeminiDelegate: GeminiServiceDelegate {
    private(set) var errors: [String] = []

    func geminiServiceDidConnect(_ service: GeminiService) {
        _ = service
    }

    func geminiServiceDidDisconnect(_ service: GeminiService) {
        _ = service
    }

    func geminiService(_ service: GeminiService, didReceiveError error: Error) {
        _ = service
        errors.append(error.localizedDescription)
    }

    func geminiService(_ service: GeminiService, didReceiveTranscript transcript: String, isFinal: Bool) {
        _ = (service, transcript, isFinal)
    }

    func geminiService(_ service: GeminiService, didReceiveInputTranscript transcript: String, isFinal: Bool) {
        _ = (service, transcript, isFinal)
    }

    func geminiService(_ service: GeminiService, didReceiveResponse text: String) {
        _ = (service, text)
    }

    func geminiService(_ service: GeminiService, didReceiveAudio data: Data) {
        _ = (service, data)
    }

    func geminiService(_ service: GeminiService, didStartFunctionCall id: String, name: String, arguments: [String : Any]) {
        _ = (service, id, name, arguments)
    }

    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: FunctionResult) {
        _ = (service, name, result)
    }

    func geminiServiceDidStartResponse(_ service: GeminiService) {
        _ = service
    }

    func geminiServiceDidEndResponse(_ service: GeminiService) {
        _ = service
    }
}

private struct MockSocketError: LocalizedError {
    var errorDescription: String? {
        "Socket is not connected"
    }
}
