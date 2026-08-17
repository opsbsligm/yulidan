import Foundation

/// 会话 — 替代 DeepSeek Harness 的 SessionRecord
public struct SessionRecord: Sendable, Identifiable, Hashable {
    public let id: SessionID
    public let metadata: SessionMetadata
    public var events: [SessionEvent]
    public var currentTurn: Int
    public var currentStep: Int
    public var status: SessionStatus

    public init(
        id: SessionID = SessionID(),
        metadata: SessionMetadata,
        events: [SessionEvent] = [],
        currentTurn: Int = 0,
        currentStep: Int = 0,
        status: SessionStatus = .active
    ) {
        self.id = id
        self.metadata = metadata
        self.events = events
        self.currentTurn = currentTurn
        self.currentStep = currentStep
        self.status = status
    }

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: SessionRecord, rhs: SessionRecord) -> Bool {
        lhs.id == rhs.id
    }

    /// 追加事件 (追加型日志)
    public mutating func append(_ event: SessionEvent) {
        events.append(event)
    }

    /// 从日志推导消息历史
    func deriveMessages() -> [Message] {
        var messages: [Message] = []
        for event in events {
            switch event {
            case let .userMessage(msg):
                messages.append(Message(role: .user, content: msg.content, id: msg.id))
            case let .assistantMessage(msg):
                messages.append(Message(role: .assistant, content: msg.content, id: msg.id))
            default:
                break
            }
        }
        return messages
    }
}

/// 会话元数据
public struct SessionMetadata: Sendable, Codable {
    public let cwd: URL
    public let createdAt: Date
    public let forkedFrom: SessionID?
    public let origin: SessionOrigin

    public init(cwd: URL, createdAt: Date = Date(), forkedFrom: SessionID? = nil, origin: SessionOrigin = .user) {
        self.cwd = cwd
        self.createdAt = createdAt
        self.forkedFrom = forkedFrom
        self.origin = origin
    }
}

/// 会话来源
public enum SessionOrigin: String, Sendable, Codable {
    case user
    case plugin
    case forked
    case resumed
}

/// 会话状态
public enum SessionStatus: String, Sendable, Codable {
    case active
    case paused
    case completed
    case failed
}

/// 消息 (简化版)
public struct Message: Sendable, Identifiable {
    public let id: MessageID
    public let role: MessageRole
    public let content: [ContentBlock]

    public enum MessageRole: String, Sendable, Codable {
        case system
        case user
        case assistant
        case tool
    }

    public init(role: MessageRole, content: [ContentBlock], id: MessageID = MessageID()) {
        self.id = id
        self.role = role
        self.content = content
    }
}
