import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var dictationController = DictationController()
    @StateObject private var settings = ChatSettings()
    
    struct CallButtonPreference {
        let iconStyle: CallPresentationStyle
        let actionStyle: CallPresentationStyle
    }
    
    // TODO: Wire these to app settings / user defaults.
    // nil keeps the call-style menu; set to force icon + action.
    @State private var preferCallButton: CallButtonPreference? = nil
    
    // Input State
    @State private var inputText = ""
    @State private var dictationBaseText = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedAttachment: ChatAttachment?
    @State private var showAttachmentMenu = false
    @State private var showPhotosPicker = false
    @State private var showDocumentPicker = false
    @State private var showCameraPhotoPicker = false
    @State private var showCameraVideoPicker = false
    @State private var callPresentationStyle: CallPresentationStyle = .fullScreen
    @State private var pipCenter: CGPoint = .zero
    @State private var pipDragStart: CGPoint?
    @State private var pipInitialized = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ChatThreadView(
                        messages: viewModel.messages,
                        isTyping: viewModel.isTyping,
                        showReadReceipts: settings.showReadReceipts
                    )
                    
                    Divider()

                    if let attachment = selectedAttachment {
                        AttachmentPreview(
                            attachment: attachment,
                            onClear: { selectedAttachment = nil }
                        )
                    }
                    
                    ChatInputBar(
                        inputText: $inputText,
                        hasAttachment: selectedAttachment != nil,
                        isDictating: dictationController.isRecording,
                        onAddAttachment: { showAttachmentMenu = true },
                        onToggleDictation: handleDictationToggle,
                        onStartVoice: { viewModel.startVoiceSession() },
                        onSend: { text in
                            viewModel.sendMessage(text, attachment: selectedAttachment)
                            inputText = ""
                            selectedAttachment = nil
                        }
                    )
                }
                
                if viewModel.callState.isPresented && callPresentationStyle == .translucentOverlay {
                    CallOverlayView(
                        viewModel: viewModel,
                        onMinimize: { callPresentationStyle = .pictureInPicture },
                        onSwitchToVideo: { callPresentationStyle = .translucentOverlay },
                        onAddAttachment: { showAttachmentMenu = true }
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
                CallView(
                    viewModel: viewModel,
                    style: .fullScreen,
                    onSwitchToVideo: { callPresentationStyle = .translucentOverlay },
                    onAddAttachment: { showAttachmentMenu = true }
                )
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
            }
            .confirmationDialog("Add attachment", isPresented: $showAttachmentMenu, titleVisibility: .visible) {
                Button("Camera Photo") { showCameraPhotoPicker = true }
                Button("Camera Video") { showCameraVideoPicker = true }
                Button("Photos") { showPhotosPicker = true }
                Button("Files") { showDocumentPicker = true }
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .any(of: [.images, .videos]))
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(allowedTypes: [.item]) { url in
                    handleDocumentSelection(url)
                }
            }
            .sheet(isPresented: $showCameraPhotoPicker) {
                CameraCapturePicker(mode: .photo) { image, videoURL in
                    if let image {
                        selectedAttachment = ChatAttachmentService.loadFromCameraImage(image)
                    }
                    showCameraPhotoPicker = false
                }
            }
            .sheet(isPresented: $showCameraVideoPicker) {
                CameraCapturePicker(mode: .video) { image, videoURL in
                    if let videoURL, let attachment = try? ChatAttachmentService.loadFromCameraVideo(videoURL) {
                        selectedAttachment = attachment
                    }
                    showCameraVideoPicker = false
                }
            }
            .onChange(of: selectedItem) {
                guard let item = selectedItem else { return }
                Task {
                    if let attachment = try? await ChatAttachmentService.loadFromPhotos(item: item) {
                        selectedAttachment = attachment
                    }
                    selectedItem = nil
                }
            }
            .onChange(of: dictationController.transcript) {
                guard dictationController.isRecording else { return }
                let trimmed = dictationController.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    inputText = dictationBaseText
                } else if dictationBaseText.isEmpty {
                    inputText = trimmed
                } else {
                    inputText = "\(dictationBaseText) \(trimmed)"
                }
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

    private func handleDictationToggle() {
        Task {
            if dictationController.isRecording {
                dictationController.stop()
            } else {
                dictationBaseText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                await dictationController.start()
            }
        }
    }

    private func handleDocumentSelection(_ url: URL?) {
        guard let url else { return }
        if let attachment = try? ChatAttachmentService.loadFromDocument(url: url) {
            selectedAttachment = attachment
        }
    }
}

private struct AttachmentPreview: View {
    let attachment: ChatAttachment
    let onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            previewContent
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(previewLabel)
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
    
    private var previewContent: some View {
        Group {
            switch attachment.kind {
            case .image:
                if let data = attachment.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray4)
                }
            case .video:
                ZStack {
                    if let data = attachment.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray4)
                    }
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                }
            case .pdf, .document:
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var previewLabel: String {
        switch attachment.kind {
        case .image:
            return "Photo attached"
        case .video:
            return "Video attached"
        case .pdf:
            return attachment.filename ?? "PDF attached"
        case .document:
            return attachment.filename ?? "Document attached"
        }
    }
}

#Preview {
    ChatView()
}
