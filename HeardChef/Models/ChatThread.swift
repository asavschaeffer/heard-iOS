import Foundation
import SwiftData

enum ChatMessageRole: String, Codable {
    case user
    case assistant
    case system
    
    var isUser: Bool {
        self == .user
    }
}

enum ChatMessageStatus: String, Codable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

enum ChatMediaType: String, Codable {
    case image
    case video
    case audio
    case document
}

@Model
final class ChatThread {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage]
    
    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
    
    func touch() {
        updatedAt = .now
    }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String?
    
    @Attribute(.externalStorage)
    var imageData: Data?
    
    var mediaTypeRaw: String?
    var mediaURL: String?
    var mediaFilename: String?
    var mediaUTType: String?
    var statusRaw: String
    @Attribute(.externalStorage)
    private var reactionsData: String = ""
    
    var reactions: [String] {
        get {
            reactionsData.isEmpty ? [] : reactionsData.components(separatedBy: ",")
        }
        set {
            reactionsData = newValue.joined(separator: ",")
        }
    }
    var isDraft: Bool
    var createdAt: Date
    var updatedAt: Date
    
    var thread: ChatThread?
    
    var role: ChatMessageRole {
        get { ChatMessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }
    
    var status: ChatMessageStatus {
        get { ChatMessageStatus(rawValue: statusRaw) ?? .sent }
        set { statusRaw = newValue.rawValue }
    }
    
    var mediaType: ChatMediaType? {
        get {
            guard let raw = mediaTypeRaw else { return nil }
            return ChatMediaType(rawValue: raw)
        }
        set {
            mediaTypeRaw = newValue?.rawValue
        }
    }
    
    init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        text: String? = nil,
        imageData: Data? = nil,
        mediaType: ChatMediaType? = nil,
        mediaURL: String? = nil,
        mediaFilename: String? = nil,
        mediaUTType: String? = nil,
        status: ChatMessageStatus = .sent,
        reactions: [String] = [],
        isDraft: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        thread: ChatThread? = nil
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.text = text
        self.imageData = imageData
        self.mediaTypeRaw = mediaType?.rawValue
        self.mediaURL = mediaURL
        self.mediaFilename = mediaFilename
        self.mediaUTType = mediaUTType
        self.statusRaw = status.rawValue
        self.reactionsData = reactions.joined(separator: ",")
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.thread = thread
    }
    
    func updateText(_ text: String?, isDraft: Bool) {
        self.text = text
        self.isDraft = isDraft
        self.updatedAt = .now
    }
    
    func markStatus(_ status: ChatMessageStatus) {
        statusRaw = status.rawValue
        updatedAt = .now
    }

    func toggleReaction(_ emoji: String) {
        if let index = reactions.firstIndex(of: emoji) {
            reactions.remove(at: index)
        } else {
            reactions.append(emoji)
        }
        updatedAt = .now
    }
}
