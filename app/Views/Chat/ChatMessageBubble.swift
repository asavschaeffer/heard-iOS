import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LinkPresentation
import AVKit

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isGroupEnd: Bool
    let statusText: String?
    let onRetry: ((ChatMessage) -> Void)?
    @ObservedObject var linkStore: LinkMetadataStore
    @Binding var activeReactionMessageID: UUID?
    @State private var quickLookItem: QuickLookItem?
    @State private var fullScreenVideoItem: FullScreenVideoItem?
    @Environment(\.openURL) private var openURL
    
    
    var body: some View {
        HStack {
            if message.role.isUser { Spacer() }
            
            VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
                        if let text = message.text {
                            Text(text)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                                .padding(.bottom, isGroupEnd ? 16 : 10)
                                .background(bubbleBackground)
                                .foregroundStyle(.white)
                                .opacity(message.isDraft ? 0.6 : 1.0)
                        }
                        
                        if let linkMetadata = linkMetadata {
                            LinkPreviewView(metadata: linkMetadata)
                                .frame(maxWidth: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    openLinkInSafari()
                                }
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
                    
                    // Red exclamation mark indicator for failed messages
                    if message.status == .failed && message.role.isUser {
                        failureIndicator
                            .onTapGesture {
                                onRetry?(message)
                            }
                    }
                }
            }
            
            if !message.role.isUser { Spacer() }
        }
        .sheet(item: $quickLookItem) { item in
            QuickLookPreview(url: item.url)
        }
        .fullScreenCover(item: $fullScreenVideoItem) { item in
            FullScreenVideoView(url: item.url)
        }
        .onLongPressGesture {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            withAnimation(.spring(duration: 0.25)) {
                activeReactionMessageID = message.id
            }
        }
        .overlay(alignment: .top) {
            if activeReactionMessageID == message.id {
                HStack(spacing: 4) {
                    ForEach(["👍", "❤️", "😂", "😮", "😢", "😡"], id: \.self) { emoji in
                        Button {
                            message.toggleReaction(emoji)
                            withAnimation { activeReactionMessageID = nil }
                        } label: {
                            Text(emoji)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.scale.combined(with: .opacity))
                .offset(y: -50)
                .zIndex(10)
            }
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
        let fillColor = message.role.isUser ? Color(red: 0.039, green: 0.518, blue: 1.0) : Color(red: 0.149, green: 0.149, blue: 0.161)
        return Group {
            if isGroupEnd {
                BubbleTailShape(isUser: message.role.isUser)
                    .fill(fillColor)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(fillColor)
            }
        }
    }

    @ViewBuilder
    private var attachmentView: some View {
        if message.mediaType == .image || (message.mediaType == nil && message.imageData != nil) {
            if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .cornerRadius(12)
                    .onTapGesture {
                        openImagePreview(data: imageData)
                    }
            }
        } else if message.mediaType == .video {
            VideoAttachmentView(thumbnailData: message.imageData)
                .onTapGesture {
                    openVideoPreview()
                }
        } else if message.mediaType == .document {
            DocumentAttachmentView(filename: message.mediaFilename, utType: message.mediaUTType)
                .onTapGesture {
                    openDocumentPreview()
                }
        }
    }

    private func openVideoPreview() {
        guard let url = ChatAttachmentPathResolver.resolveURL(
            storedReference: message.mediaURL,
            fallbackFilename: message.mediaFilename
        ) else { return }
        fullScreenVideoItem = FullScreenVideoItem(url: url)
    }

    private func openImagePreview(data: Data) {
        if let existing = ChatAttachmentPathResolver.resolveURL(
            storedReference: message.mediaURL,
            fallbackFilename: message.mediaFilename
        ), existing.isFileURL {
            quickLookItem = QuickLookItem(url: existing)
            return
        }

        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("HeardImagePreview", isDirectory: true)
        do {
            if !fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            let ext = preferredImageExtension()
            let filename = "\(message.id.uuidString).\(ext)"
            let url = folder.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            quickLookItem = QuickLookItem(url: url)
        } catch {
            print("[UI] Failed to prepare image preview file: \(error)")
        }
    }

    private func openDocumentPreview() {
        guard let url = ChatAttachmentPathResolver.resolveURL(
            storedReference: message.mediaURL,
            fallbackFilename: message.mediaFilename
        ) else { return }
        quickLookItem = QuickLookItem(url: url)
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
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
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
        .cornerRadius(12)
    }
}

private struct DocumentAttachmentView: View {
    let filename: String?
    let utType: String?
    
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
        .cornerRadius(10)
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
