import SwiftUI

enum ChefExpression: String, CaseIterable {
    case angry, crying, cute, excited, feminine, joyful, laughing, pouting, silly, winking, xd
    var assetName: String { "face-\(rawValue)" }
}

struct ChefCharacterView: View {
    let size: CGFloat
    var expression: ChefExpression?

    @State private var randomFace = ChefExpression.allCases.randomElement()!

    private var activeFace: String {
        (expression ?? randomFace).assetName
    }

    var body: some View {
        ZStack {
            Image("chef-hat")
                .resizable()
                .scaledToFit()
                .scaleEffect(1.35)

            Image(activeFace)
                .resizable()
                .scaledToFit()
                .scaleEffect(0.78)
                .offset(x: size * 0.03, y: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}
