import Foundation

/// 消息 — 替代 DeepSeek 的 Message
public struct Message: Sendable, Codable, Identifiable {
    public let id: String
    public let role: Role
    public let content: [ContentBlock]
    public let source: Source

    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
        case tool
    }

    public struct Source: Sendable, Codable {
        public let kind: String
        public var plugin: String?

        public static let user = Source(kind: "user")
        public static let plugin = Source(kind: "plugin")
        public static let model = Source(kind: "model")
        public static let tool = Source(kind: "tool")

        public init(kind: String, plugin: String? = nil) {
            self.kind = kind
            self.plugin = plugin
        }
    }

    public init(id: String = UUID().uuidString, role: Role, content: [ContentBlock], source: Source = .user) {
        self.id = id
        self.role = role
        self.content = content
        self.source = source
    }
}

/// 内容块 — 替代 DeepSeek 的 ContentBlockMap
public enum ContentBlock: Sendable, Codable {
    case text(String)
    case reasoning(String)
    case image(ImageBlock)
    case toolCall(ToolCallBlock)
    case toolResult(ToolResultBlock)
}

public struct ImageBlock: Sendable, Codable {
    public let mimeType: String
    public let data: Data
    public let width: Int?
    public let height: Int?

    public init(mimeType: String, data: Data, width: Int? = nil, height: Int? = nil) {
        self.mimeType = mimeType
        self.data = data
        self.width = width
        self.height = height
    }
}

public struct ToolCallBlock: Sendable, Codable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolResultBlock: Sendable, Codable {
    public let toolCallId: String
    public let content: [ContentBlock]
    public let isError: Bool

    public init(toolCallId: String, content: [ContentBlock], isError: Bool) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}
