import SwiftUI

struct ChefAvatarView: View {
    static let slotSize: CGFloat = 32
    private let imageSize: CGFloat = 28
    var expression: ChefExpression?

    var body: some View {
        ChefCharacterView(size: imageSize, expression: expression)
            .frame(width: Self.slotSize, height: Self.slotSize, alignment: .bottom)
            .offset(y: 4)
            .contentShape(Rectangle())
            .accessibilityLabel("Chef Guy")
    }
}
