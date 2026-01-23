import SwiftUI
import PhotosUI

struct ChatInputBar: View {
    @Binding var inputText: String
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var selectedImageData: Data?
    let onStartVoice: () -> Void
    let onSend: (String, Data?) -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }
            .onChange(of: selectedItem) {
                Task {
                    if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                        selectedItem = nil
                    }
                }
            }
            
            TextField("Message Chef...", text: $inputText, axis: .vertical)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...5)
            
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageData == nil {
                Button {
                    onStartVoice()
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                }
            } else {
                Button {
                    onSend(inputText, selectedImageData)
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
