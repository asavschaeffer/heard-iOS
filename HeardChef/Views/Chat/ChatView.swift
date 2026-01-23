import SwiftUI
import SwiftData
import PhotosUI

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ChatViewModel()
    
    struct CallButtonPreference {
        let iconStyle: CallPresentationStyle
        let actionStyle: CallPresentationStyle
    }
    
    // TODO: Wire these to app settings / user defaults.
    // nil keeps the call-style menu; set to force icon + action.
    @State private var preferCallButton: CallButtonPreference? = nil
    
    // Input State
    @State private var inputText = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var callPresentationStyle: CallPresentationStyle = .fullScreen
    @State private var pipCenter: CGPoint = .zero
    @State private var pipDragStart: CGPoint?
    @State private var pipInitialized = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ChatThreadView(messages: viewModel.messages, isTyping: viewModel.isTyping)
                    
                    Divider()

                    if let previewData = selectedImageData,
                       let previewImage = UIImage(data: previewData) {
                        AttachedMediaPreview(
                            previewImage: previewImage,
                            onClear: { selectedImageData = nil }
                        )
                    }
                    
                    ChatInputBar(
                        inputText: $inputText,
                        selectedItem: $selectedItem,
                        selectedImageData: $selectedImageData,
                        onStartVoice: { viewModel.startVoiceSession() },
                        onSend: { text, imageData in
                            viewModel.sendMessage(text, imageData: imageData)
                            inputText = ""
                            selectedImageData = nil
                        }
                    )
                }
                
                if viewModel.callState.isPresented && callPresentationStyle == .translucentOverlay {
                    CallOverlayView(
                        viewModel: viewModel,
                        onMinimize: { callPresentationStyle = .pictureInPicture }
                    )
                    .transition(.opacity)
                }
                
                if viewModel.callState.isPresented && callPresentationStyle == .pictureInPicture {
                    PiPCallOverlayView(
                        viewModel: viewModel,
                        pipCenter: $pipCenter,
                        pipDragStart: $pipDragStart,
                        pipInitialized: $pipInitialized,
                        onExpand: { callPresentationStyle = .translucentOverlay }
                    )
                    .transition(.opacity)
                }
            }
            .navigationTitle("Heard, Chef")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let prefer = preferCallButton {
                        Button {
                            callPresentationStyle = prefer.actionStyle
                            viewModel.startVoiceSession()
                        } label: {
                            Image(systemName: prefer.iconStyle == .fullScreen ? "phone.fill" : "video.fill")
                        }
                    } else {
                        Menu {
                            Button {
                                callPresentationStyle = .fullScreen
                                viewModel.startVoiceSession()
                            } label: {
                                Label("Call", systemImage: "phone.fill")
                            }
                            
                            Button {
                                callPresentationStyle = .translucentOverlay
                                viewModel.startVoiceSession()
                            } label: {
                                Label("FaceTime", systemImage: "video.fill")
                            }
                        } label: {
                            Image(systemName: "phone.fill")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: fullScreenCallBinding) {
                CallView(viewModel: viewModel, style: .fullScreen)
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
            }
        }
    }
    
    private var fullScreenCallBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.callState.isPresented && callPresentationStyle == .fullScreen
            },
            set: { newValue in
                if !newValue {
                    viewModel.stopVoiceSession()
                }
            }
        )
    }
}

private struct AttachedMediaPreview: View {
    let previewImage: UIImage
    let onClear: () -> Void
    
    var body: some View {
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
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

#Preview {
    ChatView()
}
