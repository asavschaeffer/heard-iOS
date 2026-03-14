import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LinkPresentation
import AVKit
import Foundation

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isGroupEnd: Bool
    let statusText: String?
    let onRetry: ((ChatMessage) -> Void)?
    @ObservedObject var linkStore: LinkMetadataStore
    @State private var quickLookItem: QuickLookItem?
    @State private var fullScreenVideoItem: FullScreenVideoItem?
    @Environment(\.openURL) private var openURL
    
    
    var body: some View {
        VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
                    if let text = message.text {
                        MarkdownBubbleText(
                            text: text,
                            foregroundColor: ChatBubbleStyle.foregroundColor(for: message.role)
                        )
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, isGroupEnd ? 16 : 10)
                            .background(bubbleBackground)
                            .opacity(message.isDraft ? 0.6 : 1.0)
                    }

                    if let linkMetadata = linkMetadata {
                        Button(action: openLinkInSafari) {
                            LinkPreviewView(metadata: linkMetadata)
                                .frame(maxWidth: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open link preview")
                        .accessibilityHint("Opens the linked webpage")
                        .contextMenu {
                            if let url = firstURL(in: message.text ?? "") {
                                Button("Copy Link") {
                                    UIPasteboard.general.url = url
                                }
                                ShareLink(item: url) {
                                    Label("Share…", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }

                    attachmentView

                    if !message.reactions.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(message.reactions, id: \.self) { emoji in
                                Text(emoji)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                    }

                    if let statusText {
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(message.status == .failed ? .red : .secondary)
                    }
                }

                if message.status == .failed && message.role.isUser {
                    Button {
                        onRetry?(message)
                    } label: {
                        failureIndicator
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry message")
                }
            }
        }
        .sheet(item: $quickLookItem) { item in
            QuickLookPreview(url: item.url)
        }
        .fullScreenCover(item: $fullScreenVideoItem) { item in
            FullScreenVideoView(url: item.url)
        }
        .contextMenu {
            reactionMenuSection

            if hasTextActions {
                textActionMenuSection
            }

            if hasAttachmentActions {
                attachmentActionMenuSection
            }
        } preview: {
            MessageContextPreview(message: message)
        }
    }
    
    private var failureIndicator: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 20, height: 20)
            .overlay(
                Text("!")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            )
    }
    
    private var bubbleBackground: some View {
        return Group {
            if isGroupEnd {
                BubbleTailShape(isUser: message.role.isUser)
                    .fill(messageBubbleFillColor(for: message.role))
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(messageBubbleFillColor(for: message.role))
            }
        }
    }

    @ViewBuilder
    private var attachmentView: some View {
        if effectiveMediaType == .image {
            if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                Button {
                    openImagePreview(data: imageData)
                } label: {
                    AttachmentImageView(uiImage: uiImage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open image attachment")
                .accessibilityIdentifier(attachmentAccessibilityIdentifier)
            }
        } else if effectiveMediaType == .video {
            Button(action: openVideoPreview) {
                VideoAttachmentView(
                    thumbnailData: message.imageData,
                    accessibilityIdentifier: attachmentAccessibilityIdentifier
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open video attachment")
            .accessibilityIdentifier(attachmentAccessibilityIdentifier)
        } else if effectiveMediaType == .document {
            Button(action: openDocumentPreview) {
                DocumentAttachmentView(
                    filename: message.mediaFilename,
                    utType: message.mediaUTType,
                    accessibilityIdentifier: attachmentAccessibilityIdentifier
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open document attachment")
            .accessibilityIdentifier(attachmentAccessibilityIdentifier)
        }
    }

    private func openVideoPreview() {
        guard let url = resolvedAttachmentURL() else { return }
        fullScreenVideoItem = FullScreenVideoItem(url: url)
    }

    private func openImagePreview(data: Data) {
        guard let url = shareableAttachmentURL(fallbackImageData: data) else { return }
        quickLookItem = QuickLookItem(url: url)
    }

    private func openDocumentPreview() {
        guard let url = resolvedAttachmentURL() else { return }
        quickLookItem = QuickLookItem(url: url)
    }

    private var effectiveMediaType: ChatMediaType? {
        if let mediaType = message.mediaType {
            return mediaType
        }

        if message.imageData != nil {
            return .image
        }

        return nil
    }

    private var hasTextActions: Bool {
        !(message.text?.isEmpty ?? true)
    }

    private var hasAttachmentActions: Bool {
        switch effectiveMediaType {
        case .image:
            return message.imageData != nil
        case .video, .document:
            return resolvedAttachmentURL() != nil
        case .audio, .none:
            return false
        }
    }

    private var attachmentAccessibilityIdentifier: String {
        switch effectiveMediaType {
        case .image where hasTextActions:
            return "chat.message.attachment.image.captioned"
        case .image:
            return "chat.message.attachment.image"
        case .video:
            return "chat.message.attachment.video"
        case .document:
            return "chat.message.attachment.document"
        case .audio, .none:
            return "chat.message.attachment.unknown"
        }
    }

    @ViewBuilder
    private var reactionMenuSection: some View {
        Section {
            ForEach(["👍", "❤️", "😂", "😮", "😢", "😡"], id: \.self) { emoji in
                Button {
                    message.toggleReaction(emoji)
                } label: {
                    Text(emoji)
                }
            }
        }
    }

    @ViewBuilder
    private var textActionMenuSection: some View {
        if let text = message.text {
            let copyLabel = hasAttachmentActions ? "Copy Text" : "Copy"
            let shareLabel = hasAttachmentActions ? "Share Text…" : "Share…"

            Section {
                Button {
                    copyText()
                } label: {
                    Label(copyLabel, systemImage: "doc.on.doc")
                }

                ShareLink(item: text) {
                    Label(shareLabel, systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentActionMenuSection: some View {
        if let shareURL = shareableAttachmentURL() {
            let copyLabel = hasTextActions ? "Copy Attachment" : "Copy"
            let shareLabel = hasTextActions ? "Share Attachment…" : "Share…"

            Section {
                Button {
                    copyAttachment()
                } label: {
                    Label(copyLabel, systemImage: "doc.on.doc")
                }

                ShareLink(item: shareURL) {
                    Label(shareLabel, systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func resolvedAttachmentURL() -> URL? {
        ChatAttachmentPathResolver.resolveURL(
            storedReference: message.mediaURL,
            fallbackFilename: message.mediaFilename
        )
    }

    private func shareableAttachmentURL(fallbackImageData: Data? = nil) -> URL? {
        switch effectiveMediaType {
        case .image:
            if let url = resolvedAttachmentURL(), url.isFileURL {
                return url
            }
            return temporaryImagePreviewURL(from: fallbackImageData ?? message.imageData)
        case .video, .document:
            return resolvedAttachmentURL()
        case .audio, .none:
            return nil
        }
    }

    private func temporaryImagePreviewURL(from data: Data?) -> URL? {
        guard let data else { return nil }

        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("HeardImagePreview", isDirectory: true)
        do {
            if !fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            let ext = preferredImageExtension()
            let filename = "\(message.id.uuidString).\(ext)"
            let url = folder.appendingPathComponent(filename)
            if !fm.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            }
            return url
        } catch {
            print("[UI] Failed to prepare image preview file: \(error)")
            return nil
        }
    }

    private func copyText() {
        UIPasteboard.general.string = message.text
    }

    private func copyAttachment() {
        switch effectiveMediaType {
        case .image:
            guard let data = message.imageData, let image = UIImage(data: data) else { return }
            UIPasteboard.general.image = image
        case .video, .document:
            guard let url = shareableAttachmentURL(),
                  let provider = NSItemProvider(contentsOf: url) else { return }
            UIPasteboard.general.itemProviders = [provider]
        case .audio, .none:
            return
        }
    }

    private func preferredImageExtension() -> String {
        if let ut = message.mediaUTType, let type = UTType(ut) {
            if type.conforms(to: .png) { return "png" }
            if type.conforms(to: .heic) { return "heic" }
        }
        return "jpg"
    }

    private func openLinkInSafari() {
        guard let url = firstURL(in: message.text ?? "") else { return }
        openURL(url)
    }

    private var linkMetadata: LPLinkMetadata? {
        if let url = firstURL(in: message.text ?? ""), isPreviewableWebURL(url) {
            let key = url.absoluteString
            if let cached = linkStore.metadata(for: key) {
                return cached
            }
            linkStore.prefetch(url: url, key: key)
        }

        return nil
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
}

private struct AttachmentImageView: View {
    let uiImage: UIImage
    var accessibilityIdentifier: String?

    var body: some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 200)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct MarkdownBubbleText: View {
    let text: String
    let foregroundColor: Color

    var body: some View {
        Group {
            if let attributedText = attributedText {
                Text(attributedText)
            } else {
                Text(text)
            }
        }
        .font(.body)
        .foregroundStyle(foregroundColor)
        .lineSpacing(4)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        guard var attributed = try? AttributedString(markdown: normalizedMarkdown, options: options) else {
            return nil
        }

        attributed.foregroundColor = foregroundColor
        return attributed
    }

    private var normalizedMarkdown: String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct FullScreenVideoItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct FullScreenVideoView: View {
    let url: URL
    @State private var player: AVPlayer
    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear {
                    player.play()
                }
                .onDisappear {
                    player.pause()
                }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(20)
            }
        }
    }
}

private struct VideoAttachmentView: View {
    let thumbnailData: Data?
    var accessibilityIdentifier: String?
    
    var body: some View {
        ZStack {
            if let data = thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(.systemGray4)
            }
            Image(systemName: "play.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.black.opacity(0.4), in: Circle())
        }
        .frame(maxWidth: 220)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

private struct DocumentAttachmentView: View {
    let filename: String?
    let utType: String?
    var accessibilityIdentifier: String?
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(filename ?? "Document")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Text(typeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private var typeLabel: String {
        if let utType, let type = UTType(utType), type.conforms(to: .pdf) {
            return "PDF"
        }
        let ext = filename?.split(separator: ".").last.map { String($0).uppercased() }
        return ext ?? "DOC"
    }
}

struct BubbleTailShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 18
        let tailRadius: CGFloat = 6.0
        let w = rect.width
        let h = rect.height

        var path = Path()

        if isUser {
            // Start at top-left + cornerRadius
            path.move(to: CGPoint(x: cornerRadius, y: 0))
            // Top edge
            path.addLine(to: CGPoint(x: w - cornerRadius, y: 0))
            // Top-right corner
            path.addQuadCurve(
                to: CGPoint(x: w, y: cornerRadius),
                control: CGPoint(x: w, y: 0)
            )
            // Right edge down to tail start (no bottom-right corner radius — sharp into tail)
            path.addLine(to: CGPoint(x: w, y: h - tailRadius))
            // Tail: curves outward and swoops back
            path.addQuadCurve(
                to: CGPoint(x: w + 4, y: h),
                control: CGPoint(x: w, y: h)
            )
            path.addQuadCurve(
                to: CGPoint(x: w - 8, y: h - tailRadius),
                control: CGPoint(x: w - 2, y: h)
            )
            // Bottom edge
            path.addLine(to: CGPoint(x: cornerRadius, y: h - tailRadius))
            // Bottom-left corner
            path.addQuadCurve(
                to: CGPoint(x: 0, y: h - tailRadius - cornerRadius),
                control: CGPoint(x: 0, y: h - tailRadius)
            )
            // Left edge
            path.addLine(to: CGPoint(x: 0, y: cornerRadius))
            // Top-left corner
            path.addQuadCurve(
                to: CGPoint(x: cornerRadius, y: 0),
                control: CGPoint(x: 0, y: 0)
            )
        } else {
            // Start at top-left + cornerRadius
            path.move(to: CGPoint(x: cornerRadius, y: 0))
            // Top edge
            path.addLine(to: CGPoint(x: w - cornerRadius, y: 0))
            // Top-right corner
            path.addQuadCurve(
                to: CGPoint(x: w, y: cornerRadius),
                control: CGPoint(x: w, y: 0)
            )
            // Right edge
            path.addLine(to: CGPoint(x: w, y: h - tailRadius - cornerRadius))
            // Bottom-right corner
            path.addQuadCurve(
                to: CGPoint(x: w - cornerRadius, y: h - tailRadius),
                control: CGPoint(x: w, y: h - tailRadius)
            )
            // Bottom edge
            path.addLine(to: CGPoint(x: 8, y: h - tailRadius))
            // Tail: curves outward to the left and swoops back
            path.addQuadCurve(
                to: CGPoint(x: -4, y: h),
                control: CGPoint(x: 2, y: h)
            )
            path.addQuadCurve(
                to: CGPoint(x: 0, y: h - tailRadius),
                control: CGPoint(x: 0, y: h)
            )
            // Left edge (no bottom-left corner radius — sharp from tail)
            path.addLine(to: CGPoint(x: 0, y: cornerRadius))
            // Top-left corner
            path.addQuadCurve(
                to: CGPoint(x: cornerRadius, y: 0),
                control: CGPoint(x: 0, y: 0)
            )
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Context Menu Preview

private struct MessageContextPreview: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let text = message.text {
                MarkdownBubbleText(
                    text: text,
                    foregroundColor: ChatBubbleStyle.foregroundColor(for: message.role)
                )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(messageBubbleFillColor(for: message.role))
                    )
            }

            MessageAttachmentPreview(
                message: message,
                accessibilityIdentifier: contextPreviewAttachmentIdentifier
            )
        }
        .frame(width: 300)
        .frame(maxHeight: 400)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var contextPreviewAttachmentIdentifier: String? {
        let hasText = !(message.text?.isEmpty ?? true)
        let mediaType = message.mediaType ?? (message.imageData != nil ? .image : nil)

        switch mediaType {
        case .image where hasText:
            return "chat.contextPreview.attachment.image.captioned"
        case .image:
            return "chat.contextPreview.attachment.image"
        case .video:
            return "chat.contextPreview.attachment.video"
        case .document:
            return "chat.contextPreview.attachment.document"
        case .audio, .none:
            return nil
        }
    }
}

private struct MessageAttachmentPreview: View {
    let message: ChatMessage
    let accessibilityIdentifier: String?

    var body: some View {
        Group {
            if message.mediaType == .image || (message.mediaType == nil && message.imageData != nil) {
                if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                    AttachmentImageView(
                        uiImage: uiImage,
                        accessibilityIdentifier: accessibilityIdentifier
                    )
                }
            } else if message.mediaType == .video {
                VideoAttachmentView(
                    thumbnailData: message.imageData,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            } else if message.mediaType == .document {
                DocumentAttachmentView(
                    filename: message.mediaFilename,
                    utType: message.mediaUTType,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            }
        }
    }
}

private func messageBubbleFillColor(for role: ChatMessageRole) -> Color {
    ChatBubbleStyle.fillColor(for: role)
}
