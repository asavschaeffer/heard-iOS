import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LinkPresentation

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isGroupEnd: Bool
    let statusText: String?
    let onRetry: ((ChatMessage) -> Void)?
    @State private var quickLookItem: QuickLookItem?
    @State private var shareURL: IdentifiableURL?
    @ObservedObject var linkStore: LinkMetadataStore
    
    
    var body: some View {
        HStack {
            if message.role.isUser { Spacer() }
            
            VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
                        if let text = message.text {
                            Text(text)
                                .padding(12)
                                .background(bubbleBackground)
                                .foregroundStyle(message.role.isUser ? .white : .primary)
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
                                        Button("Share…") {
                                            shareURL = IdentifiableURL(url: url)
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
        .sheet(item: $shareURL) { identifiableURL in
            ShareSheet(items: [identifiableURL.url])
        }
        .contextMenu {
            Button("👍") { message.toggleReaction("👍") }
            Button("❤️") { message.toggleReaction("❤️") }
            Button("😂") { message.toggleReaction("😂") }
            Button("😮") { message.toggleReaction("😮") }
            Button("😢") { message.toggleReaction("😢") }
            Button("😡") { message.toggleReaction("😡") }
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
        let fillColor = message.role.isUser ? Color.blue : Color(.systemGray5)
        return Group {
            if isGroupEnd {
                BubbleTailShape(isUser: message.role.isUser)
                    .fill(fillColor)
            } else {
                RoundedRectangle(cornerRadius: 16)
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
            }
        } else if message.mediaType == .video {
            VideoAttachmentView(thumbnailData: message.imageData)
                .onTapGesture {
                    openQuickLook()
                }
        } else if message.mediaType == .document {
            DocumentAttachmentView(filename: message.mediaFilename, utType: message.mediaUTType)
                .onTapGesture {
                    openQuickLook()
                }
        }
    }

    private func openQuickLook() {
        guard let urlString = message.mediaURL,
              let url = URL(string: urlString) else {
            return
        }
        quickLookItem = QuickLookItem(url: url)
    }

    private func openLinkInSafari() {
        guard let url = firstURL(in: message.text ?? "") else { return }
        UIApplication.shared.open(url)
    }

    private var linkMetadata: LPLinkMetadata? {
        if let url = firstURL(in: message.text ?? "") {
            let key = url.absoluteString
            if let cached = linkStore.metadata(for: key) {
                return cached
            }
            linkStore.prefetch(url: url, key: key)
        }

        if let urlString = message.mediaURL, let url = URL(string: urlString) {
            let key = url.absoluteString
            if let cached = linkStore.metadata(for: key) {
                return cached
            }
            linkStore.prefetch(url: url, key: key)
        }

        return nil
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
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
        let tailWidth: CGFloat = 8
        let tailHeight: CGFloat = 8
        let cornerRadius: CGFloat = 16
        let tailOffset: CGFloat = 4
        
        var bubbleRect = rect
        bubbleRect.size.height -= tailHeight
        
        var path = Path(roundedRect: bubbleRect, cornerRadius: cornerRadius)
        
        let tailX = isUser ? bubbleRect.maxX - tailOffset : bubbleRect.minX + tailOffset
        let tailTipX = isUser ? tailX + tailWidth : tailX - tailWidth
        
        path.move(to: CGPoint(x: tailX, y: bubbleRect.maxY))
        path.addLine(to: CGPoint(x: tailTipX, y: bubbleRect.maxY + tailHeight))
        path.addLine(to: CGPoint(x: tailX, y: bubbleRect.maxY))
        
        return path
    }
}
