import SwiftUI

struct ChatInputBar: View {
    @Binding var inputText: String
    let hasAttachment: Bool
    let isDictating: Bool
    @Binding var showAttachmentMenu: Bool
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void
    let onToggleDictation: () -> Void
    let onSend: (String) -> Void

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachment
    }

    private var actionIconName: String {
        canSend ? "arrow.up.circle.fill" : "waveform.circle.fill"
    }

    private var actionIconColor: Color {
        if canSend {
            return iMessageBlue
        }
        return isDictating ? .red : .gray
    }

    private var actionAccessibilityLabel: String {
        if canSend {
            return "Send message"
        }
        return isDictating ? "Stop dictation" : "Start dictation"
    }

    private let iMessageBlue = Color(red: 0.039, green: 0.518, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            if showAttachmentMenu {
                AttachmentMenuRow(
                    onCamera: onCamera,
                    onPhotos: onPhotos,
                    onFiles: onFiles
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAttachmentMenu.toggle()
                    }
                } label: {
                    Image(systemName: showAttachmentMenu ? "xmark" : "plus")
                        .font(.title2)
                        .foregroundStyle(.gray)
                        .frame(width: 36, height: 36)
                }

                HStack(spacing: 0) {
                    TextField("Message Chef...", text: $inputText, axis: .vertical)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .lineLimit(1...5)

                    Button {
                        if canSend {
                            onSend(inputText)
                        } else {
                            onToggleDictation()
                        }
                    } label: {
                        Image(systemName: actionIconName)
                            .font(.system(size: 24))
                            .foregroundStyle(actionIconColor)
                    }
                    .padding(.trailing, 4)
                    .accessibilityLabel(actionAccessibilityLabel)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(.systemGray3), lineWidth: 0.5)
                )
            }
            .padding()
        }
        .background(.bar)
        .sensoryFeedback(.selection, trigger: showAttachmentMenu)
    }
}

private struct AttachmentMenuRow: View {
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            attachmentButton(icon: "camera.fill", label: "Camera", action: onCamera)
            attachmentButton(icon: "photo.on.rectangle", label: "Photos", action: onPhotos)
            attachmentButton(icon: "doc.fill", label: "Files", action: onFiles)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private static let circleBackground = Color(uiColor: .systemGray5)
    private static let labelColor = Color(uiColor: .label)

    private func attachmentButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Self.labelColor)
                    .frame(width: 52, height: 52)
                    .background(Self.circleBackground)
                    .clipShape(Circle())

                Text(label)
                    .font(.caption)
                    .foregroundStyle(Self.labelColor)
            }
        }
    }
}
