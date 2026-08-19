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
    /// 置顶（Codex 式 pinned 段；默认 false）
    public let pinned: Bool

    public init(cwd: URL, createdAt: Date = Date(), forkedFrom: SessionID? = nil, origin: SessionOrigin = .user, pinned: Bool = false) {
        self.cwd = cwd
        self.createdAt = createdAt
        self.forkedFrom = forkedFrom
        self.origin = origin
        self.pinned = pinned
    }

    /// 自定义解码：兼容不含 pinned 字段的旧 metadata_json（缺省 false）
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try c.decode(URL.self, forKey: .cwd)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        forkedFrom = try c.decodeIfPresent(SessionID.self, forKey: .forkedFrom)
        origin = try c.decodeIfPresent(SessionOrigin.self, forKey: .origin) ?? .user
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    /// 返回置顶态切换后的副本
    public func withPinned(_ pinned: Bool) -> SessionMetadata {
        SessionMetadata(cwd: cwd, createdAt: createdAt, forkedFrom: forkedFrom,
                        origin: origin, pinned: pinned)
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
