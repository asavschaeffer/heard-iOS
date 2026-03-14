import Foundation
import Combine
import SwiftUI

@MainActor
final class AppNavigationState: ObservableObject {
    enum Tab: Hashable {
        case chat
        case inventory
        case recipes
        case settings
    }

    struct PendingChatSubmission {
        enum Source {
            case inventory
        }

        let id = UUID()
        let source: Source
        let draftText: String
        let attachment: ChatAttachment
        let shouldAutoSend: Bool
    }

    @Published var selectedTab: Tab
    @Published var pendingChatSubmission: PendingChatSubmission?
    @Published var pendingCallRequest = false

    init() {
        selectedTab = TestSupport.defaultTabIndex == 1 ? .inventory : .chat
    }

    func openChatSubmission(
        from source: PendingChatSubmission.Source,
        draftText: String,
        attachment: ChatAttachment,
        shouldAutoSend: Bool = true
    ) {
        selectedTab = .chat
        pendingChatSubmission = PendingChatSubmission(
            source: source,
            draftText: draftText,
            attachment: attachment,
            shouldAutoSend: shouldAutoSend
        )
    }

    func consumePendingChatSubmission(id: UUID) {
        guard pendingChatSubmission?.id == id else { return }
        pendingChatSubmission = nil
    }

    func requestCall() {
        selectedTab = .chat
        pendingCallRequest = true
    }
}
