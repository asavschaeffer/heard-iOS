import SwiftUI
import UIKit

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isGroupEnd: Bool
    let statusText: String?
    
    var body: some View {
        HStack {
            if message.role.isUser { Spacer() }
            
            VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 6) {
                if let text = message.text {
                    Text(text)
                        .padding(12)
                        .background(bubbleBackground)
                        .foregroundStyle(message.role.isUser ? .white : .primary)
                        .opacity(message.isDraft ? 0.6 : 1.0)
                }
                
                attachmentView

                if let statusText {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if !message.role.isUser { Spacer() }
        }
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
        } else if message.mediaType == .document {
            DocumentAttachmentView(filename: message.mediaFilename)
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
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(filename ?? "PDF Document")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Text("PDF")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
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
