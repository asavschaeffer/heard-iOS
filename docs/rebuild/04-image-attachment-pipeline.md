# Image & Attachment Pipeline: Deep Dive

## Overview

The app supports sending images, videos, and documents to Gemini. There are multiple input sources (PhotosPicker, camera, document picker) and two delivery paths (REST API for text mode, WebSocket for call mode).

## Current State

### What works:
- Camera photo capture → `ChatAttachmentService.loadFromCameraImage()` → attachment → REST send ✓
- Camera video capture → `ChatAttachmentService.loadFromCameraVideo()` → attachment → REST send ✓
- Document picker → `ChatAttachmentService.loadFromDocument()` → attachment → REST send ✓
- Text-only messages via REST ✓
- Text-only messages via WebSocket during call ✓

### What's broken:
- **PhotosPicker selection is discarded without loading** (critical bug)
- **`loadFromPhotos` is commented out** in ChatAttachmentService

## The Bug

### ChatView.swift lines 87-91

```swift
private func handleSelectedItemChange() {
    guard selectedItem != nil else { return }
    Task {
        selectedItem = nil  // ← Just clears! Never loads the image data
    }
}
```

### ChatAttachmentService.swift lines 31-56

```swift
/* static func loadFromPhotos(item: PhotosPickerItem) async throws -> ChatAttachment {
    let contentTypes = item.supportedContentTypes
    if contentTypes.contains(where: { $0.conforms(to: .image) }) {
        if let data = try await item.loadTransferable(type: Data.self) {
            return ChatAttachment(kind: .image, imageData: data, fileURL: nil, filename: "photo.jpg", utType: UTType.jpeg.identifier)
        }
        throw ChatAttachmentError.loadFailed
    }
    if contentTypes.contains(where: { $0.conforms(to: .movie) }) {
        if let url = try await item.loadTransferable(type: URL.self) {
            let copiedURL = try copyToDocuments(url: url)
            let thumbnail = videoThumbnailData(from: copiedURL)
            return ChatAttachment(
                kind: .video,
                imageData: thumbnail,
                fileURL: copiedURL,
                filename: copiedURL.lastPathComponent,
                utType: UTType.movie.identifier
            )
        }
        throw ChatAttachmentError.loadFailed
    }
    throw ChatAttachmentError.unsupported
} */
```

The method exists but is **commented out**.

## The Fix

### 1. Uncomment `loadFromPhotos` in ChatAttachmentService.swift

Remove the `/* ... */` comment wrapper around the method.

### 2. Fix `handleSelectedItemChange` in ChatView.swift

```swift
private func handleSelectedItemChange() {
    guard let item = selectedItem else { return }
    selectedItem = nil  // Clear to prevent re-triggering
    Task {
        do {
            selectedAttachment = try await ChatAttachmentService.loadFromPhotos(item: item)
        } catch {
            print("Failed to load attachment: \(error)")
        }
    }
}
```

## Complete Attachment Flow (After Fix)

### Input Sources

```
PhotosPicker → .onChange(of: selectedItem) → handleSelectedItemChange()
                                            → ChatAttachmentService.loadFromPhotos(item:)
                                            → selectedAttachment = ChatAttachment

Camera Photo → CameraCapturePicker(mode: .photo) → ChatAttachmentService.loadFromCameraImage(_:)
                                                   → selectedAttachment = ChatAttachment

Camera Video → CameraCapturePicker(mode: .video) → ChatAttachmentService.loadFromCameraVideo(_:)
                                                   → selectedAttachment = ChatAttachment

Document     → DocumentPicker → handleDocumentSelection(_:)
                               → ChatAttachmentService.loadFromDocument(url:)
                               → selectedAttachment = ChatAttachment
```

### Sending (all sources converge here)

```
User taps Send
    ↓
ChatView.onSend: viewModel.sendMessage(text, attachment: selectedAttachment)
    ↓
ChatViewModel.sendMessage():
    buildMessage(text:, attachment:) → ChatMessage with imageData, mediaType, etc.
    insertMessage() → SwiftData persistence
    messages.append() → UI update
    enqueueOrSend() → routes to appropriate path
    ↓
    ┌─ Not in call → sendToGemini() → REST path
    │   ├─ text + image → sendTextWithPhotoREST() → base64 JPEG inline_data
    │   ├─ image only  → sendPhotoREST() → base64 JPEG inline_data
    │   ├─ text only   → sendTextREST() → text parts
    │   └─ video/doc   → sendVideoAttachment()/sendDocumentAttachment() → STUB (not supported)
    │
    └─ In call (WebSocket connected) → sendToGemini() → WebSocket path
        ├─ text + image → sendTextWithPhoto() → client_content with text + inline_data parts
        ├─ image only  → sendPhoto() → client_content with inline_data part
        ├─ text only   → sendText() → client_content with text part
        └─ video/doc   → sendVideoAttachment()/sendDocumentAttachment() → STUB
```

### REST API Path (text mode)

```json
POST /v1beta/models/gemini-2.5-flash:generateContent

{
  "contents": [
    ...conversationHistory,
    {
      "role": "user",
      "parts": [
        {"text": "what's this ingredient?"},
        {"inline_data": {"mime_type": "image/jpeg", "data": "base64..."}}
      ]
    }
  ],
  "systemInstruction": {"parts": [{"text": "system prompt"}]},
  "tools": [{"functionDeclarations": [...]}]
}
```

### WebSocket Path (during call)

```json
{
  "client_content": {
    "turns": [{
      "role": "user",
      "parts": [
        {"text": "what's this ingredient?"},
        {"inline_data": {"mime_type": "image/jpeg", "data": "base64..."}}
      ]
    }],
    "turn_complete": true
  }
}
```

## Image Processing

### Compression & Resizing

`CameraService.processImageForGemini()` handles optimization:
- Max size: 1024x1024 pixels
- JPEG compression: 0.8 quality
- Preserves aspect ratio

For PhotosPicker images, the raw `Data` from `loadTransferable` is used directly. Consider adding the same processing:

```swift
static func loadFromPhotos(item: PhotosPickerItem) async throws -> ChatAttachment {
    // ... load data ...
    // Optionally resize/compress for consistency:
    if let uiImage = UIImage(data: data) {
        let processed = processForGemini(uiImage)
        return ChatAttachment(kind: .image, imageData: processed, ...)
    }
}
```

## Multimodal During Voice Call — Caveat

When sending images via WebSocket during a voice call, the audio model (`gemini-2.5-flash-native-audio-preview`) may or may not support image inputs. This depends on the specific model version. If images are silently ignored during calls, this is a model limitation, not a code bug.

**Video frames** sent via `realtime_input` media chunks ARE supported by the Live API for vision-capable models.

## Video/Document Attachments — Not Yet Supported

`sendVideoAttachment()` and `sendDocumentAttachment()` are stubs:
```swift
func sendVideoAttachment(url: URL, utType: String?) {
    guard isConnected else { return }
    guard supportsFileAttachments else { return }  // ← always false
    // TODO
}
```

The Gemini REST API supports file uploads via the File API, but this isn't implemented yet. For now, videos and documents can be displayed locally but aren't sent to Gemini.

## Verification

After fixing:
1. Open PhotosPicker → select a photo → attachment preview appears above input bar
2. Type a message → send → image appears in chat bubble
3. Gemini responds with analysis of the image
4. Select a video from PhotosPicker → video thumbnail preview appears
5. Camera capture still works (was never broken)
6. Document picker still works (was never broken)
