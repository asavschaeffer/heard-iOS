import SwiftUI

struct ChatThreadView: View {
    let messages: [ChatMessage]
    let isTyping: Bool
    let showReadReceipts: Bool
    @ObservedObject var linkStore: LinkMetadataStore
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages.indices, id: \.self) { index in
                        let message = messages[index]
                        let nextMessage = index + 1 < messages.count ? messages[index + 1] : nil
                        let previousMessage = index > 0 ? messages[index - 1] : nil
                        let isGroupEnd = nextMessage?.role.isUser != message.role.isUser
                        let showTimestamp = shouldShowTimestamp(for: message, previous: previousMessage)
                        let statusText = statusText(for: message, isGroupEnd: isGroupEnd)

                        if showTimestamp {
                            HStack {
                                Spacer()
                                Text(timestampText(for: message.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }

                        ChatMessageBubble(
                            message: message,
                            isGroupEnd: isGroupEnd,
                            statusText: statusText,
                            linkStore: linkStore
                        )
                        .id(message.id)
                        .padding(.bottom, isGroupEnd ? 8 : 2)
                    }

                    if isTyping {
                        TypingIndicatorBubble()
                            .padding(.bottom, 8)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let lastId = messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
        }
    }
    
    private func shouldShowTimestamp(for message: ChatMessage, previous: ChatMessage?) -> Bool {
        guard let previous else { return true }
        let gap = message.createdAt.timeIntervalSince(previous.createdAt)
        return gap > 5 * 60
    }

    private func timestampText(for date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    private func statusText(for message: ChatMessage, isGroupEnd: Bool) -> String? {
        guard message.role.isUser, isGroupEnd else { return nil }
        switch message.status {
        case .sending:
            return "Sending..."
        case .sent:
            return nil
        case .delivered:
            return showReadReceipts ? "Delivered" : nil
        case .read:
            return showReadReceipts ? "Read" : nil
        case .failed:
            return "Failed"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
