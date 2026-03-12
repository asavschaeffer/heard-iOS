import SwiftUI
import Foundation
import SwiftData

struct ChatThreadView: View {
    let messages: [ChatMessage]
    let isTyping: Bool
    let toolCallChips: [ChatViewModel.ToolCallChip]
    let showReadReceipts: Bool
    @ObservedObject var linkStore: LinkMetadataStore
    let onRetry: (ChatMessage) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        messageView(for: message, at: index)
                    }

                    if isTyping {
                        TypingIndicatorBubble()
                            .padding(.bottom, 8)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                if let lastId = messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                } else if let lastToolID = toolCallChips.last?.id {
                    withAnimation { proxy.scrollTo(lastToolID, anchor: .bottom) }
                }
            }
            .onChange(of: toolCallChips.count) {
                if let last = toolCallChips.last {
                    let anchorID = last.anchorMessageID
                    if let anchor = anchorID, messages.contains(where: { $0.id == anchor }) {
                        withAnimation { proxy.scrollTo(anchor, anchor: .bottom) }
                    } else {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(for message: ChatMessage, at index: Int) -> some View {
        let nextMessage = index + 1 < messages.count ? messages[index + 1] : nil
        let previousMessage = index > 0 ? messages[index - 1] : nil
        let isGroupEnd = nextMessage?.role.isUser != message.role.isUser
        let latestUserMessageID = messages.last(where: { $0.role.isUser })?.id
        let isMostRecentUserMessage = message.id == latestUserMessageID
        let showTimestamp = shouldShowTimestamp(for: message, previous: previousMessage)
        let statusText = statusText(
            for: message,
            isGroupEnd: isGroupEnd,
            isMostRecentUserMessage: isMostRecentUserMessage
        )

        if showTimestamp {
            HStack {
                Spacer()
                Text(timestampText(for: message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }

        let attachedToolChips = toolCallChips.filter { $0.anchorMessageID == message.id }

        VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
            if message.role == .assistant && !attachedToolChips.isEmpty {
                ToolCallChipsView(chips: attachedToolChips)
            }

            ChatMessageBubble(
                message: message,
                isGroupEnd: isGroupEnd,
                statusText: statusText,
                onRetry: { onRetry($0) },
                linkStore: linkStore
            )
        }
        .id(message.id)
        .padding(.bottom, isGroupEnd ? 10 : 0)
        .onAppear {
            prefetchLinks(for: message)
        }
    }
    
    private func prefetchLinks(for message: ChatMessage) {
        var urls: [URL] = []
        if let text = message.text, let url = firstURL(in: text), isPreviewableWebURL(url) {
            urls.append(url)
        }
        linkStore.prefetchMany(urls: urls)
    }

    private func isPreviewableWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
    
    private func firstURL(in text: String) -> URL? {
        guard let detector = SharedDataDetector.linkDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }
    
    private func shouldShowTimestamp(for message: ChatMessage, previous: ChatMessage?) -> Bool {
        guard let previous else { return true }
        let gap = message.createdAt.timeIntervalSince(previous.createdAt)
        return gap > 5 * 60
    }

    private func timestampText(for date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    private func statusText(
        for message: ChatMessage,
        isGroupEnd: Bool,
        isMostRecentUserMessage: Bool
    ) -> String? {
        guard message.role.isUser, isGroupEnd, isMostRecentUserMessage else { return nil }
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
            return "Not Delivered"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ToolCallChipsView: View {
    let chips: [ChatViewModel.ToolCallChip]
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chips) { chip in
                ToolCallChipRow(
                    chip: chip,
                    isExpanded: expandedIDs.contains(chip.id),
                    onToggleExpand: {
                        guard !chip.details.isEmpty else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expandedIDs.contains(chip.id) {
                                expandedIDs.remove(chip.id)
                            } else {
                                expandedIDs.insert(chip.id)
                            }
                        }
                    }
                )
                .id(chip.id)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

private struct ToolCallChipRow: View {
    let chip: ChatViewModel.ToolCallChip
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chip.details.isEmpty {
                chipLabel
            } else {
                Button(action: onToggleExpand) {
                    chipLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(chip.actionText), \(isExpanded ? "collapse details" : "expand details")")
            }

            if isExpanded, !chip.details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(chip.details.enumerated()), id: \.offset) { _, detail in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detail.key)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(detail.value)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var statusColor: Color {
        switch chip.status {
        case .pending:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var chipLabel: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: chip.iconName)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(width: 14, height: 14, alignment: .center)
            Text(chip.actionText)
                .font(.caption)
                .baselineOffset(0.8)
                .foregroundStyle(.primary)
            if !chip.details.isEmpty {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
        .opacity(chip.status == .pending ? (pulse ? 0.55 : 1.0) : 1.0)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Capsule())
        .onAppear {
            guard chip.status == .pending else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
