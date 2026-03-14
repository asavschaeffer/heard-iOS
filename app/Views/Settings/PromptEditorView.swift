import SwiftUI

struct PromptEditorView: View {
    let title: String
    @Binding var text: String
    let defaultText: String
    @State private var showResetConfirmation = false

    var body: some View {
        TextEditor(text: $text)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .padding(.horizontal)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .disabled(text == defaultText)
                }
            }
            .alert("Reset \(title)?", isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive) {
                    text = defaultText
                }
            } message: {
                Text("This will replace the current prompt with the default.")
            }
    }
}
