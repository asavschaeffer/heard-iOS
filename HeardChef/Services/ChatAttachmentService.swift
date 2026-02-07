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
    private static let attachmentsFolder = "ChatAttachments"

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

    private static func copyToDocuments(url: URL) throws -> URL {
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

    private static func videoThumbnailData(from url: URL) -> Data? {
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
}
