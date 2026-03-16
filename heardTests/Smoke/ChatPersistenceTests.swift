import Foundation
import SwiftData
import Testing
import VoiceCore
@testable import heard

@Suite(.tags(.hosted, .smoke))
@MainActor
struct ChatPersistenceTests {
    @Test
    func bootstrapPersistsThreadAndGreetingAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = PersistenceMockGeminiService(modelContext: context)
        let viewModel = makeViewModel(service: service)

        viewModel.setModelContext(context)

        let verificationContext = ModelContext(container)
        let thread = try #require(fetchThread(in: verificationContext))
        let messages = try fetchMessages(in: verificationContext, threadID: thread.id)

        #expect(thread.title == "Heard, Chef")
        #expect(messages.count == 1)
        #expect(messages.first?.role == .assistant)
        #expect(messages.first?.text == "What are we cooking today?")
    }

    @Test
    func sendMessagePersistsUserMessageAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = PersistenceMockGeminiService(modelContext: context)
        let viewModel = makeViewModel(service: service)

        viewModel.setModelContext(context)
        viewModel.sendMessage("Need dinner ideas")

        let verificationContext = ModelContext(container)
        let thread = try #require(fetchThread(in: verificationContext))
        let messages = try fetchMessages(in: verificationContext, threadID: thread.id)
        let userMessage = try #require(messages.last(where: { $0.role == .user }))

        #expect(service.sentTexts == ["Need dinner ideas"])
        #expect(messages.count == 2)
        #expect(userMessage.text == "Need dinner ideas")
        #expect(userMessage.status == .sending)
    }

    @Test
    func assistantResponseFinalizationPersistsNonDraftMessageAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = PersistenceMockGeminiService(modelContext: context)
        let viewModel = makeViewModel(service: service)

        viewModel.setModelContext(context)
        viewModel.geminiService(service, didReceiveResponse: "Use the mushrooms in a risotto.")
        viewModel.geminiServiceDidEndResponse(service)

        let verificationContext = ModelContext(container)
        let thread = try #require(fetchThread(in: verificationContext))
        let messages = try fetchMessages(in: verificationContext, threadID: thread.id)
        let assistantMessage = try #require(messages.last(where: { $0.role == .assistant }))

        #expect(assistantMessage.text == "Use the mushrooms in a risotto.")
        #expect(assistantMessage.isDraft == false)
    }

    @Test
    func whitespaceDraftCleanupDeletesPersistedDraftAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = PersistenceMockGeminiService(modelContext: context)
        let viewModel = makeViewModel(service: service)

        viewModel.setModelContext(context)
        viewModel.geminiService(service, didReceiveInputTranscript: " ", isFinal: false)
        viewModel.geminiService(service, didReceiveInputTranscript: "", isFinal: true)

        let verificationContext = ModelContext(container)
        let thread = try #require(fetchThread(in: verificationContext))
        let messages = try fetchMessages(in: verificationContext, threadID: thread.id)
        let userMessages = messages.filter { $0.role == .user }

        #expect(userMessages.isEmpty)
    }

    private func makeViewModel(service: PersistenceMockGeminiService) -> ChatViewModel {
        ChatViewModel(
            geminiServiceFactory: { _ in service },
            voiceCoordinator: PersistenceMockVoiceCoordinator(),
            shouldBootstrapThreadOnModelContext: true
        )
    }

    private func fetchThread(in context: ModelContext) -> ChatThread? {
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.title == "Heard, Chef" }
        )
        return try? context.fetch(descriptor).first
    }

    private func fetchMessages(in context: ModelContext, threadID: UUID) throws -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.thread?.id == threadID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }
}

@MainActor
private final class PersistenceMockGeminiService: GeminiService {
    private(set) var sentTexts: [String] = []

    override func sendText(_ text: String, messageID: UUID? = nil) -> Result<Void, Error> {
        _ = messageID
        sentTexts.append(text)
        return .success(())
    }
}

@MainActor
private final class PersistenceMockVoiceCoordinator: ChatVoiceCoordinating {
    weak var delegate: VoiceCallCoordinatorDelegate?
    var onCapturedAudio: ((Data) -> Void)?
    var onCallKitStartRequested: (() -> Void)?
    var onCallKitTransactionAccepted: (() -> Void)?
    var onCallKitPerformStart: (() -> Void)?
    var onCallKitActivated: (() -> Void)?
    var onPlaybackStarted: (() -> Void)?

    func prewarmPlayback() {}
    func transportWillConnect() {}
    func startCall() {}
    func stopCall() {}
    func toggleMute() {}
    func toggleSpeaker() {}
    func transportDidConnect() {}
    func transportDidDisconnect(autoReconnect: Bool) {
        _ = autoReconnect
    }
    func transportDidFail(message: String) {
        _ = message
    }
    func transportDidReceiveAudio(_ data: Data) {
        _ = data
    }
}

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Ingredient.self,
        Recipe.self,
        RecipeIngredient.self,
        RecipeStep.self,
        ChatThread.self,
        ChatMessage.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
