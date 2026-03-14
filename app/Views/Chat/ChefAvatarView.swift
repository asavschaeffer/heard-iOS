import SwiftUI

struct ChefAvatarView: View {
    static let slotSize: CGFloat = 32
    private let imageSize: CGFloat = 28

    var body: some View {
        Image("launch-chef")
            .resizable()
            .scaledToFit()
            .frame(width: imageSize, height: imageSize)
            .frame(width: Self.slotSize, height: Self.slotSize, alignment: .bottom)
            .contentShape(Rectangle())
            .accessibilityLabel("Chef Guy")
    }
}
