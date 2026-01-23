import SwiftUI

struct TypingIndicatorBubble: View {
    @State private var animate = false
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 1.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                            value: animate
                        )
                }
            }
            .padding(12)
            .background(Color(.systemGray5))
            .cornerRadius(16)
            Spacer()
        }
        .onAppear { animate = true }
    }
}
