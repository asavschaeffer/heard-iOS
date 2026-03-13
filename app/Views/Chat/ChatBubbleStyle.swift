import SwiftUI

enum ChatBubbleStyle {
    static let userFill = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let incomingFill = Color(.secondarySystemBackground)
    static let incomingAccent = Color.primary.opacity(0.45)

    static func fillColor(for role: ChatMessageRole) -> Color {
        role.isUser ? userFill : incomingFill
    }

    static func foregroundColor(for role: ChatMessageRole) -> Color {
        role.isUser ? .white : .primary
    }
}
