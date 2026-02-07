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
    @StateObject private var linkStore = LinkMetadataStore()
    
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
            mainContentWithModifiers
        }
    }
    
    private var mainContentWithModifiers: some View {
        mainContent
            .navigationTitle("Heard, Chef")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationToolbar }
            .fullScreenCover(isPresented: fullScreenCallBinding) { callFullScreenCover }
            .onAppear {
                viewModel.setModelContext(modelContext)
            }
            .confirmationDialog("Add attachment", isPresented: $showAttachmentMenu, titleVisibility: .visible) {
                attachmentDialogButtons
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .any(of: [.images, .videos]))
            .sheet(isPresented: $showDocumentPicker) { documentPicker }
            .sheet(isPresented: $showCameraPhotoPicker) { cameraPhotoPicker }
            .sheet(isPresented: $showCameraVideoPicker) { cameraVideoPicker }
            .onChange(of: selectedItem) { handleSelectedItemChange() }
            .onChange(of: dictationController.transcript) { handleTranscriptChange() }
    }
    
    @ViewBuilder
    private var attachmentDialogButtons: some View {
        Button("Camera Photo") { showCameraPhotoPicker = true }
        Button("Camera Video") { showCameraVideoPicker = true }
        Button("Photos") { showPhotosPicker = true }
        Button("Files") { showDocumentPicker = true }
    }
    
    private var documentPicker: some View {
        DocumentPicker(allowedTypes: [.item]) { url in
            handleDocumentSelection(url)
        }
    }
    
    private var cameraPhotoPicker: some View {
        CameraCapturePicker(mode: .photo) { image, videoURL in
            if let image {
                selectedAttachment = ChatAttachmentService.loadFromCameraImage(image)
            }
            showCameraPhotoPicker = false
        }
    }
    
    private var cameraVideoPicker: some View {
        CameraCapturePicker(mode: .video) { image, videoURL in
            if let videoURL, let attachment = try? ChatAttachmentService.loadFromCameraVideo(videoURL) {
                selectedAttachment = attachment
            }
            showCameraVideoPicker = false
        }
    }
    
    private func handleSelectedItemChange() {
        guard selectedItem != nil else { return }
        Task {
            // TODO: Fix PhotosPickerItem compatibility for iOS 18.6
            // if let attachment = try? await ChatAttachmentService.loadFromPhotos(item: selectedItem!) {
            //     selectedAttachment = attachment
            // }
            selectedItem = nil
        }
    }
    
    private func handleTranscriptChange() {
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
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            chatInterface
            callOverlayViews
        }
    }
    
    @ViewBuilder
    private var chatInterface: some View {
        VStack(spacing: 0) {
            ChatThreadView(
                messages: viewModel.messages,
                isTyping: viewModel.isTyping,
                showReadReceipts: settings.showReadReceipts,
                linkStore: linkStore
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
    }
    
    @ViewBuilder
    private var callOverlayViews: some View {
        if viewModel.callState.isPresented && callPresentationStyle == .translucentOverlay {
            CallOverlayView(
                viewModel: viewModel,
                onMinimize: { callPresentationStyle = .pictureInPicture },
                onToggleVideo: { toggleVideoMode() },
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
                onExpand: { callPresentationStyle = .translucentOverlay },
                onToggleVideo: { toggleVideoMode() }
            )
            .transition(.opacity)
        }
    }
    
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                callPresentationStyle = .fullScreen
                viewModel.startVoiceSession()
            } label: {
                Image(systemName: "phone.fill")
            }
        }
    }
    
    private var callFullScreenCover: some View {
        CallView(
            viewModel: viewModel,
            style: .fullScreen,
            onToggleVideo: { toggleVideoMode() },
            onAddAttachment: { showAttachmentMenu = true }
        )
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

    private func toggleVideoMode() {
        callPresentationStyle = callPresentationStyle == .translucentOverlay ? .fullScreen : .translucentOverlay
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
