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
                LazyVStack(spacing: 12) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        messageView(for: message, at: index)
                    }

                    if !toolCallChips.isEmpty {
                        ToolCallChipsView(chips: toolCallChips)
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
                }
            }
            .onChange(of: toolCallChips.count) {
                if let last = toolCallChips.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
    
    @ViewBuilder
    private func messageView(for message: ChatMessage, at index: Int) -> some View {
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
            onRetry: { onRetry($0) },
            linkStore: linkStore
        )
        .id(message.id)
        .padding(.bottom, isGroupEnd ? 8 : 2)
        .onAppear {
            prefetchLinks(for: message)
        }
    }
    
    private func prefetchLinks(for message: ChatMessage) {
        var urls: [URL] = []
        if let text = message.text, let url = firstURL(in: text) {
            urls.append(url)
        }
        if let urlString = message.mediaURL, let url = URL(string: urlString) {
            urls.append(url)
        }
        linkStore.prefetchMany(urls: urls)
    }
    
    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
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
                        if expandedIDs.contains(chip.id) {
                            expandedIDs.remove(chip.id)
                        } else {
                            expandedIDs.insert(chip.id)
                        }
                    }
                )
                .id(chip.id)
            }
        }
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
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(chip.summary)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                if chip.details != nil {
                    Button(isExpanded ? "Hide" : "Details") {
                        onToggleExpand()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            .opacity(chip.status == .pending ? (pulse ? 0.55 : 1.0) : 1.0)
            .onAppear {
                guard chip.status == .pending else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            if isExpanded, let details = chip.details {
                Text(details)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var statusIcon: String {
        switch chip.status {
        case .pending:
            return "clock.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
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
}
