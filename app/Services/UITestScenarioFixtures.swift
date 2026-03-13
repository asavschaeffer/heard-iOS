import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

enum UITestScenarioFixtures {
    static func seed(_ scenario: UITestScenario, into context: ModelContext) {
        let builder = UITestSeedBuilder(context: context)
        builder.reset()

        switch scenario {
        case .editorFlows:
            seedEditorFlows(using: builder)
        case .keyboardDismiss:
            seedKeyboardDismiss(using: builder)
        case .searchFiltering:
            seedSearchFiltering(using: builder)
        case .emptyState:
            break
        case .attachmentsBasic:
            seedAttachmentsBasic(using: builder)
        }

        builder.save()
    }

    private static func seedEditorFlows(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for UI editor flow checks."
        )
    }

    private static func seedKeyboardDismiss(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for UI keyboard dismissal checks."
        )
    }

    private static func seedSearchFiltering(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for UI search and filtering checks."
        )
    }

    private static func seedAttachmentsBasic(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for attachment UI coverage."
        )

        let thread = builder.chatThread(title: "Heard, Chef")
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let imageData = sampleImageData(
            colors: [UIColor.systemPink, UIColor.systemOrange],
            text: "IMG"
        )
        let videoThumbnailData = sampleImageData(
            colors: [UIColor.systemTeal, UIColor.systemBlue],
            text: "VID"
        )

        let videoFilename = "ui-test-video.mov"
        let videoURL = storeAttachmentFile(
            named: videoFilename,
            data: Data("ui-test-video".utf8)
        )
        let videoReference = ChatAttachmentPathResolver.storedReference(
            for: videoURL,
            filename: videoFilename
        )

        let documentFilename = "ui-test-notes.pdf"
        let documentURL = storeAttachmentFile(
            named: documentFilename,
            data: Data("%PDF-1.4\n%UITest\n".utf8)
        )
        let documentReference = ChatAttachmentPathResolver.storedReference(
            for: documentURL,
            filename: documentFilename
        )

        builder.chatMessage(
            thread: thread,
            role: .assistant,
            text: "Use long-press on the attachments below.",
            createdAt: baseDate,
            updatedAt: baseDate
        )

        builder.chatMessage(
            thread: thread,
            role: .user,
            imageData: imageData,
            mediaType: .image,
            createdAt: baseDate.addingTimeInterval(60),
            updatedAt: baseDate.addingTimeInterval(60)
        )

        builder.chatMessage(
            thread: thread,
            role: .user,
            text: "Captioned attachment for copy/share coverage.",
            imageData: imageData,
            mediaType: .image,
            createdAt: baseDate.addingTimeInterval(120),
            updatedAt: baseDate.addingTimeInterval(120)
        )

        builder.chatMessage(
            thread: thread,
            role: .user,
            imageData: videoThumbnailData,
            mediaType: .video,
            mediaURL: videoReference,
            mediaFilename: videoFilename,
            mediaUTType: UTType.movie.identifier,
            createdAt: baseDate.addingTimeInterval(180),
            updatedAt: baseDate.addingTimeInterval(180)
        )

        builder.chatMessage(
            thread: thread,
            role: .user,
            text: "Document attachment",
            mediaType: .document,
            mediaURL: documentReference,
            mediaFilename: documentFilename,
            mediaUTType: UTType.pdf.identifier,
            createdAt: baseDate.addingTimeInterval(240),
            updatedAt: baseDate.addingTimeInterval(240)
        )
    }

    private static func seedCoreEditorData(
        using builder: UITestSeedBuilder,
        recipeDescription: String
    ) {
        _ = builder.ingredient(
            name: "UI Test Butter",
            quantity: 1,
            unit: .piece,
            category: .dairy,
            location: .fridge
        )

        _ = builder.recipe(
            name: "UI Test Pasta",
            description: recipeDescription,
            ingredients: [
                RecipeIngredient(name: "Pasta", quantity: 1, unit: .boxes),
                RecipeIngredient(name: "Butter", quantity: 2, unit: .tablespoons)
            ],
            steps: [
                RecipeStep(instruction: "Boil pasta.", orderIndex: 0),
                RecipeStep(instruction: "Toss with butter.", orderIndex: 1)
            ]
        )
    }

    private static func sampleImageData(colors: [UIColor], text: String) -> Data? {
        let size = CGSize(width: 240, height: 160)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgColors = colors.map(\.cgColor) as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0, 1]
            let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations)

            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 42),
                .foregroundColor: UIColor.white
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributedText.size()
            let origin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )
            attributedText.draw(at: origin)
        }

        return image.jpegData(compressionQuality: 0.9)
    }

    private static func storeAttachmentFile(named filename: String, data: Data) -> URL? {
        let manager = FileManager.default

        guard let documentsURL = manager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let attachmentsURL = documentsURL
            .appendingPathComponent(ChatAttachmentService.attachmentsFolder, isDirectory: true)
        let fileURL = attachmentsURL.appendingPathComponent(filename)

        do {
            if !manager.fileExists(atPath: attachmentsURL.path) {
                try manager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
            }
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            assertionFailure("Failed to write UI test attachment: \(error)")
            return nil
        }
    }
}
