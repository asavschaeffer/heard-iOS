import SwiftUI
import SwiftData
import PhotosUI

struct VoiceView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = VoiceViewModel()
    
    // Input State
    @State private var inputText = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Chat History
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                ChatMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let lastId = viewModel.messages.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                }
                
                Divider()

                if let previewData = selectedImageData,
                   let previewImage = UIImage(data: previewData) {
                    HStack(spacing: 12) {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Photo attached")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            selectedImageData = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                // 2. Input Bar
                HStack(alignment: .bottom, spacing: 12) {
                    // Camera Button
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
                    
                    // Text Input
                    TextField("Message Chef...", text: $inputText, axis: .vertical)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .lineLimit(1...5)
                    
                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageData == nil {
                        // Mic Button (Starts Voice Mode)
                        Button {
                            viewModel.startVoiceSession()
                        } label: {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)
                        }
                    } else {
                        // Send Text Button
                        Button {
                            viewModel.sendMessage(inputText, imageData: selectedImageData)
                            inputText = ""
                            selectedImageData = nil
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
            .navigationTitle("Heard, Chef")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showVoiceMode) {
                VoiceSessionView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
            }
        }
    }
}

// MARK: - Chat Bubble

struct ChatMessageBubble: View {
    let message: VoiceViewModel.ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            
            VStack(alignment: message.isUser ? .trailing : .leading) {
                if let text = message.text {
                    Text(text)
                        .padding(12)
                        .background(message.isUser ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(message.isUser ? .white : .primary)
                        .cornerRadius(16)
                        .opacity(message.isDraft ? 0.6 : 1.0)
                }
                
                if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .cornerRadius(12)
                }
            }
            
            if !message.isUser { Spacer() }
        }
    }
}

// MARK: - Voice Session Modal (The "Call" UI)

struct VoiceSessionView: View {
    @ObservedObject var viewModel: VoiceViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            HStack {
                Button {
                    // Minimize / Hide
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
                Spacer()
                Text(viewModel.connectionState == .connected ? "Connected" : "Connecting...")
                    .font(.caption)
                    .foregroundStyle(viewModel.connectionState == .connected ? .green : .orange)
                Spacer()
                // Mute Toggle
                Button {
                    viewModel.toggleMute()
                } label: {
                    Image(systemName: viewModel.isListening ? "mic.fill" : "mic.slash.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.isListening ? .primary : .red)
                }
            }
            .padding()
            
            Spacer()
            
            // Avatar / Visualization
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .scaleEffect(viewModel.isSpeaking ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(), value: viewModel.isSpeaking)
                
                Image("app-icon-template") // Placeholder if asset exists
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100)
                    .foregroundStyle(.orange)
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 40) {
                // End Call
                Button {
                    viewModel.stopVoiceSession()
                } label: {
                    VStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "phone.down.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                            )
                        Text("End")
                            .font(.caption)
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .onAppear {
            // Ensure connection when modal appears
            viewModel.startVoiceSession()
        }
        .onDisappear {
            // Optional: Disconnect on swipe down? 
            // Or just mute? For now, let's stop session to save battery.
            viewModel.stopVoiceSession()
        }
    }
}

#Preview {
    VoiceView()
}
