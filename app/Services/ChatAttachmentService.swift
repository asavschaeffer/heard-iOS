import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

enum ChatAttachmentKind {
    case image
    case video
    case pdf
    case document
}

struct ChatAttachment {
    let kind: ChatAttachmentKind
    let imageData: Data?
    let fileURL: URL?
    let filename: String?
    let utType: String?
}

enum ChatAttachmentError: Error {
    case unsupported
    case loadFailed
    case fileCopyFailed
}

final class ChatAttachmentService {
    nonisolated private static let attachmentsFolder = "ChatAttachments"
    nonisolated private static let photoMaxDimension: CGFloat = 1280
    nonisolated private static let photoJPEGQuality: CGFloat = 0.82
    nonisolated private static let photoReencodeThresholdBytes = 1_500_000

    static func loadFromPhotos(
        contentTypes: [UTType],
        loadData: @escaping () async throws -> Data?,
        loadURL: @escaping () async throws -> URL?
    ) async throws -> ChatAttachment {
        let startedAt = Date()
        let typeList = contentTypes.map(\.identifier).joined(separator: ",")
        print("[Attachment] Photos load started. types=[\(typeList)]")

        if contentTypes.contains(where: { $0.conforms(to: .image) }) {
            if let data = try await loadData() {
                let transformStart = Date()
                let normalizedData = await Task.detached(priority: .userInitiated) {
                    normalizePhotoDataIfNeeded(data)
                }.value
                let transformMs = Int(Date().timeIntervalSince(transformStart) * 1000)
                let outputData = normalizedData ?? data
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                print("[Attachment] Photos image loaded. originalBytes=\(data.count) normalizedBytes=\(outputData.count) transformMs=\(transformMs) elapsedMs=\(elapsedMs)")
                return ChatAttachment(kind: .image, imageData: outputData, fileURL: nil, filename: "photo.jpg", utType: UTType.jpeg.identifier)
            }
            throw ChatAttachmentError.loadFailed
        }

        if contentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let url = try await loadURL() {
                let prepared = try await Task.detached(priority: .userInitiated) { () -> (URL, Data?) in
                    let copiedURL = try copyToDocuments(url: url)
                    let thumbnail = videoThumbnailData(from: copiedURL)
                    return (copiedURL, thumbnail)
                }.value

                let copiedURL = prepared.0
                let thumbnail = prepared.1
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: copiedURL.path)[.size] as? NSNumber)?.int64Value ?? -1
                print("[Attachment] Photos video loaded. bytes=\(fileSize) thumbBytes=\(thumbnail?.count ?? 0) elapsedMs=\(elapsedMs)")
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
    }

    static func loadFromDocument(url: URL) throws -> ChatAttachment {
        let copiedURL = try copyToDocuments(url: url)
        let utType = UTType(filenameExtension: copiedURL.pathExtension) ?? .data
        let kind: ChatAttachmentKind = utType.conforms(to: .pdf) ? .pdf : .document
        return ChatAttachment(
            kind: kind,
            imageData: nil,
            fileURL: copiedURL,
            filename: copiedURL.lastPathComponent,
            utType: utType.identifier
        )
    }

    static func loadFromCameraImage(_ image: UIImage) -> ChatAttachment {
        let data = image.jpegData(compressionQuality: 0.85)
        return ChatAttachment(kind: .image, imageData: data, fileURL: nil, filename: "camera.jpg", utType: UTType.jpeg.identifier)
    }

    static func loadFromCameraVideo(_ url: URL) throws -> ChatAttachment {
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

    nonisolated private static func copyToDocuments(url: URL) throws -> URL {
        let manager = FileManager.default
        let docs = try manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = docs.appendingPathComponent(attachmentsFolder, isDirectory: true)

        if !manager.fileExists(atPath: folder.path) {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let destination = folder.appendingPathComponent(url.lastPathComponent)
        if manager.fileExists(atPath: destination.path) {
            return destination
        }

        do {
            try manager.copyItem(at: url, to: destination)
            return destination
        } catch {
            throw ChatAttachmentError.fileCopyFailed
        }
    }

    nonisolated private static func videoThumbnailData(from url: URL) -> Data? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        return image.jpegData(compressionQuality: 0.8)
    }

    nonisolated private static func normalizePhotoDataIfNeeded(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let originalSize = image.size
        let maxEdge = max(originalSize.width, originalSize.height)
        let needsResize = maxEdge > photoMaxDimension
        let shouldReencode = needsResize || data.count >= photoReencodeThresholdBytes
        guard shouldReencode else { return data }

        let targetSize: CGSize
        if needsResize {
            let scale = photoMaxDimension / maxEdge
            targetSize = CGSize(width: max(1, floor(originalSize.width * scale)),
                                height: max(1, floor(originalSize.height * scale)))
        } else {
            targetSize = originalSize
        }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpeg = renderedImage.jpegData(compressionQuality: photoJPEGQuality) else {
            return data
        }

        if !needsResize && jpeg.count >= data.count {
            return data
        }

        return jpeg
    }
}
