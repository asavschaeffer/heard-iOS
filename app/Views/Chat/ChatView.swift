import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VoiceCore

struct ChatView: View {
    private enum CallDismissalReason {
        case none
        case minimize
        case endCall
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var dictationController = DictationController()
    @StateObject private var settings = ChatSettings()
    @StateObject private var linkStore = LinkMetadataStore()
    
    // Input State
    @State private var inputText = ""
    @State private var composerResetToken = UUID()
    @State private var dictationBaseText = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedAttachment: ChatAttachment?
    @State private var showAttachmentRow = false
    @State private var showPhotosPicker = false
    @State private var showDocumentPicker = false
    @State private var showCameraPhotoPicker = false
    @State private var attachmentErrorMessage: String?
    @State private var callPresentationStyle: CallPresentationStyle = .fullScreen
    @State private var isCallScreenPresented = false
    @State private var callDismissalReason: CallDismissalReason = .none

    var body: some View {
        NavigationStack {
            mainContentWithModifiers
        }
    }
    
    private var isPiP: Bool {
        viewModel.callState.isPresented && callPresentationStyle == .pictureInPicture
    }

    private var mainContentWithModifiers: some View {
        mainContent
            .navigationTitle(isPiP ? "" : "Heard, Chef")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if !isPiP { navigationToolbar } }
            .fullScreenCover(isPresented: fullScreenCallBinding) { callFullScreenCover }
            .task {
                await Task.yield()
                viewModel.prepareForFirstCall()
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                handlePendingChatSubmission()
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $selectedItem,
                matching: .any(of: [.images, .videos])
            )
            .sheet(isPresented: $showDocumentPicker) { documentPicker }
            .sheet(isPresented: $showCameraPhotoPicker) { cameraPhotoPicker }
            .alert("Attachment Error", isPresented: attachmentErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(attachmentErrorMessage ?? "Unable to prepare attachment.")
            }
            .onChange(of: viewModel.callState.isPresented) { _, isPresented in
                if !isPresented {
                    isCallScreenPresented = false
                }
            }
            .onChange(of: navigationState.pendingChatSubmission?.id) {
                handlePendingChatSubmission()
            }
            .onChange(of: navigationState.pendingCallRequest) {
                if navigationState.pendingCallRequest {
                    navigationState.pendingCallRequest = false
                    viewModel.noteCallPresentationRequested()
                    callPresentationStyle = .fullScreen
                    isCallScreenPresented = true
                }
            }
            .onChange(of: selectedItem) { handleSelectedItemChange() }
            .onChange(of: dictationController.transcript) { handleTranscriptChange() }
    }

    private var attachmentErrorPresented: Binding<Bool> {
        Binding(
            get: { attachmentErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    attachmentErrorMessage = nil
                }
            }
        )
    }
    
    private var documentPicker: some View {
        DocumentPicker(allowedTypes: [.content]) { url in
            handleDocumentSelection(url)
        }
    }
    
    private var cameraPhotoPicker: some View {
        CameraCaptureFlowView(
            allowVideo: true,
            onPick: { image, videoURL in
                if let videoURL, let attachment = try? ChatAttachmentService.loadFromCameraVideo(videoURL) {
                    selectedAttachment = attachment
                    print("[UI] Attachment selected from camera: kind=video file=\(attachment.filename ?? "unknown")")
                    showCameraPhotoPicker = false
                } else if let image {
                    let attachment = ChatAttachmentService.loadFromCameraImage(image)
                    selectedAttachment = attachment
                    print("[UI] Attachment selected from camera: kind=image")
                    showCameraPhotoPicker = false
                } else {
                    showCameraPhotoPicker = false
                }
            },
            onError: { attachmentErrorMessage = $0 }
        )
    }
    
    private func handleSelectedItemChange() {
        guard let item = selectedItem else { return }
        selectedItem = nil
        let contentTypes = item.supportedContentTypes
        let startedAt = Date()
        let typeList = contentTypes.map(\.identifier).joined(separator: ",")
        print("[UI] Photos picker selection received. types=[\(typeList)]")
        Task {
            do {
                let attachment = try await ChatAttachmentService.loadFromPhotos(
                    contentTypes: contentTypes,
                    loadData: { try await item.loadTransferable(type: Data.self) },
                    loadURL: { try await item.loadTransferable(type: URL.self) }
                )
                let loadedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                await MainActor.run {
                    selectedAttachment = attachment
                }
                let totalMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                print("[UI] Loaded attachment from Photos picker: kind=\(attachment.kind) loadMs=\(loadedMs) totalMs=\(totalMs)")
            } catch {
                print("[UI] Failed to load attachment from Photos picker: \(error)")
                await MainActor.run {
                    attachmentErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to load selected attachment."
                }
            }
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

    private func handlePendingChatSubmission() {
        guard let submission = navigationState.pendingChatSubmission else { return }
        navigationState.consumePendingChatSubmission(id: submission.id)

        if submission.shouldAutoSend {
            sendMessage(submission.draftText, attachment: submission.attachment)
            return
        }

        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = submission.draftText
        }
        selectedAttachment = submission.attachment
    }

    private func sendMessage(_ text: String, attachment: ChatAttachment?) {
        showAttachmentRow = false
        if dictationController.isRecording {
            dictationController.stop()
        }
        if let attachment {
            let imageBytes = attachment.imageData?.count ?? 0
            print("[UI] Send tapped with attachment. kind=\(attachment.kind) imageBytes=\(imageBytes)")
        } else {
            print("[UI] Send tapped with text-only message")
        }
        viewModel.sendMessage(text, attachment: attachment)
        inputText = ""
        dictationBaseText = ""
        dictationController.transcript = ""
        composerResetToken = UUID()
        selectedAttachment = nil
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
                toolCallChips: viewModel.toolCallChips,
                showReadReceipts: settings.showReadReceipts,
                chefExpression: viewModel.chefExpression,
                linkStore: linkStore,
                onRetry: { message in
                    // Forward retry without relying on dynamic member lookup
                    handleRetry(message)
                }
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
                composerResetToken: composerResetToken,
                hasAttachment: selectedAttachment != nil,
                isDictating: dictationController.isRecording,
                showAttachmentMenu: $showAttachmentRow,
                onCamera: {
                    showAttachmentRow = false
                    showCameraPhotoPicker = true
                },
                onPhotos: {
                    showAttachmentRow = false
                    showPhotosPicker = true
                },
                onFiles: {
                    showAttachmentRow = false
                    showDocumentPicker = true
                },
                onToggleDictation: handleDictationToggle,
                onSend: { text in
                    sendMessage(text, attachment: selectedAttachment)
                }
            )
        }
    }
    
    @ViewBuilder
    private var callOverlayViews: some View {
        if viewModel.callState.isPresented && callPresentationStyle == .pictureInPicture {
            PiPCallOverlayView(
                viewModel: viewModel,
                onExpand: {
                    callDismissalReason = .none
                    callPresentationStyle = .fullScreen
                    isCallScreenPresented = true
                },
                onEndCall: {
                    callDismissalReason = .endCall
                    viewModel.stopVoiceSession()
                },
                onToggleVideo: { viewModel.toggleVideoFromCallView() }
            )
            .transition(.opacity)
        }
    }
    
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.noteCallPresentationRequested()
                callPresentationStyle = .fullScreen
                isCallScreenPresented = true
            } label: {
                Image(systemName: "phone.fill")
            }
        }
    }
    
    private var callFullScreenCover: some View {
        CallView(
            viewModel: viewModel,
            onMinimize: {
                callDismissalReason = .minimize
                callPresentationStyle = .pictureInPicture
                isCallScreenPresented = false
            },
            onEndCall: {
                callDismissalReason = .endCall
                viewModel.stopVoiceSession()
            }
        )
    }

    private var fullScreenCallBinding: Binding<Bool> {
        Binding(
            get: {
                isCallScreenPresented && callPresentationStyle == .fullScreen
            },
            set: { newValue in
                if !newValue {
                    isCallScreenPresented = false
                    let dismissalReason = callDismissalReason
                    callDismissalReason = .none
                    if dismissalReason == .minimize {
                        callPresentationStyle = .pictureInPicture
                    } else if dismissalReason == .none && viewModel.callState.isPresented && !viewModel.isStoppingCall {
                        viewModel.stopVoiceSession()
                    }
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
            print("[UI] Attachment selected from files: kind=\(attachment.kind) file=\(attachment.filename ?? "unknown")")
        } else {
            attachmentErrorMessage = "Unable to load selected file."
            print("[UI] Failed to load attachment from files: url=\(url.lastPathComponent)")
        }
    }
    
    private func handleRetry(_ message: ChatMessage) {
        viewModel.retryMessage(message)
    }
}

private struct AttachmentPreview: View {
    let attachment: ChatAttachment
    let onClear: () -> Void
    @State private var previewImage: UIImage?
    
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
        .onAppear { preparePreviewImage() }
        .onChange(of: attachment.imageData) { _, _ in
            preparePreviewImage()
        }
    }

    private func preparePreviewImage() {
        guard let data = attachment.imageData else {
            previewImage = nil
            return
        }
        Task {
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            await MainActor.run {
                previewImage = decoded
            }
        }
    }
    
    private var previewContent: some View {
        Group {
            switch attachment.kind {
            case .image:
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray4)
                }
            case .video:
                ZStack {
                    if let image = previewImage {
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
        .environmentObject(AppNavigationState())
}
