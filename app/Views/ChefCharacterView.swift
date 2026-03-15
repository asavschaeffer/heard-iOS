import SwiftUI

struct ChefCharacterView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image("chef-hat")
                .resizable()
                .scaledToFit()
                .scaleEffect(1.35)

            Image("chef-face")
                .resizable()
                .scaledToFit()
                .scaleEffect(0.78)
                .offset(x: size * 0.03, y: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}
