import SwiftUI

struct ChatMessageRow: View {
    let message: ChatMessage
    let isGroupEnd: Bool
    let statusText: String?
    let onRetry: (ChatMessage) -> Void
    @ObservedObject var linkStore: LinkMetadataStore

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role.isUser {
                Spacer(minLength: ChefAvatarView.slotSize + 8)
                bubble
            } else {
                avatarSlot
                bubble
                Spacer(minLength: ChefAvatarView.slotSize + 8)
            }
        }
    }

    private var bubble: some View {
        ChatMessageBubble(
            message: message,
            isGroupEnd: isGroupEnd,
            statusText: statusText,
            onRetry: { onRetry($0) },
            linkStore: linkStore
        )
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if message.role == .assistant && isGroupEnd {
            ChefAvatarView()
        } else {
            Color.clear
                .frame(width: ChefAvatarView.slotSize, height: ChefAvatarView.slotSize)
                .accessibilityHidden(true)
        }
    }
}
