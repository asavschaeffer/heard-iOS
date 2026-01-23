import SwiftUI

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
                
                if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .cornerRadius(12)
                }

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
