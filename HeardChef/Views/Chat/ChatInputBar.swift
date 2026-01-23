import SwiftUI

struct ChatInputBar: View {
    @Binding var inputText: String
    let hasAttachment: Bool
    let isDictating: Bool
    let onAddAttachment: () -> Void
    let onToggleDictation: () -> Void
    let onStartVoice: () -> Void
    let onSend: (String) -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                onAddAttachment()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }
            
            TextField("Message Chef...", text: $inputText, axis: .vertical)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...5)
            
            Button {
                onToggleDictation()
            } label: {
                Image(systemName: isDictating ? "mic.fill" : "mic")
                    .font(.system(size: 20))
                    .foregroundStyle(isDictating ? .red : .gray)
                    .padding(6)
                    .background(Color(.systemGray6), in: Circle())
            }
            .accessibilityLabel(isDictating ? "Stop dictation" : "Start dictation")
            
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasAttachment {
                Button {
                    onStartVoice()
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                }
            } else {
                Button {
                    onSend(inputText)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .background(.bar)
    }
}
