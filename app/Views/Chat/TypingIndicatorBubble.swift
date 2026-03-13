import SwiftUI

struct TypingIndicatorBubble: View {
    @State private var animate = false

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 1.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                            value: animate
                        )
                }
            }
            .offset(y: -2)
            .padding(12)
            .background(
                BubbleTailShape(isUser: false)
                    .fill(Color(red: 0.149, green: 0.149, blue: 0.161))
            )
            Spacer()
        }
        .onAppear { animate = true }
    }
}
