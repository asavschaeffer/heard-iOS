import SwiftUI

struct ChefCharacterView: View {
    let size: CGFloat

    private static let faces = [
        "face-angry", "face-crying", "face-cute", "face-excited",
        "face-feminine", "face-joyful", "face-laughing", "face-pouting",
        "face-silly", "face-winking", "face-xd"
    ]

    @State private var face = faces.randomElement()!

    var body: some View {
        ZStack {
            Image("chef-hat")
                .resizable()
                .scaledToFit()
                .scaleEffect(1.35)

            Image(face)
                .resizable()
                .scaledToFit()
                .scaleEffect(0.78)
                .offset(x: size * 0.03, y: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}
