import ServiceContainer
import Foundation

/// 会话事件 — 追加型日志的事件类型
/// 替代 DeepSeek Harness 的 SessionEventMap
public enum SessionEvent: Sendable, Codable {
    // Turn 生命周期
    case turnStart(turn: Int)
    case turnEnd(turn: Int, reason: TurnEndReason)
    
    // Step 生命周期
    case stepStart(turn: Int, step: Int)
    case stepEnd(turn: Int, step: Int)
    
    // 消息
    case userMessage(UserMessage)
    case assistantChunk(AssistantChunk)
    case assistantMessage(AssistantMessage)
    
    // 工具
    case toolCall(ToolCallEvent)
    case toolResult(ToolResultEvent)
    
    // 请求
    case requestHeader(EpochHeader)
    case requestContext(RequestContext)
    
    // Todo
    case todoWrite([TodoItem])
    
    public var eventType: String {
        switch self {
        case .turnStart: return "turn/start"
        case .turnEnd: return "turn/end"
        case .stepStart: return "step/start"
        case .stepEnd: return "step/end"
        case .userMessage: return "user/message"
        case .assistantChunk: return "assistant/chunk"
        case .assistantMessage: return "assistant/message"
        case .toolCall: return "tool/call"
        case .toolResult: return "tool/result"
        case .requestHeader: return "request/header"
        case .requestContext: return "request/context"
        case .todoWrite: return "todo/write"
        }
    }
}

/// Turn 结束原因
public enum TurnEndReason: String, Sendable, Codable {
    case completed
    case rejected
    case cancelled
    case failed
}

/// 用户消息
public struct UserMessage: Sendable, Codable {
    public let id: MessageID
    public let content: [ContentBlock]
    public let source: MessageSource
    public let createdAt: Date
    
    public init(id: MessageID = MessageID(), content: [ContentBlock], source: MessageSource = .user) {
        self.id = id
        self.content = content
        self.source = source
        self.createdAt = Date()
    }
}

/// 助手消息
public struct AssistantMessage: Sendable, Codable {
    public let id: MessageID
    public let turn: Int
    public let step: Int
    public let content: [ContentBlock]
    public let provider: String
    public let model: String
    public let usage: TokenUsage?
    public let createdAt: Date
    
    public init(
        id: MessageID = MessageID(),
        turn: Int,
        step: Int,
        content: [ContentBlock],
        provider: String,
        model: String,
        usage: TokenUsage? = nil
    ) {
        self.id = id
        self.turn = turn
        self.step = step
        self.content = content
        self.provider = provider
        self.model = model
        self.usage = usage
        self.createdAt = Date()
    }
}

/// 流式块
public struct AssistantChunk: Sendable, Codable {
    public let turn: Int
    public let step: Int
    public let chunk: StreamChunk
}

/// 流式内容块
public struct StreamChunk: Sendable, Codable {
    public let type: String
    public let data: Data
    public let index: Int
}

/// 消息 ID
public struct MessageID: Sendable, Hashable, Codable {
    public let rawValue: UUID
    
    public init() {
        self.rawValue = UUID()
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

/// 文本块
public struct ImageBlock: Sendable, Codable {
    public let mimeType: String
    public let data: Data
    public let width: Int?
    public let height: Int?
}

/// 工具调用块
public struct ToolCallBlock: Sendable, Codable {
    public let id: String
    public let name: String
    public let arguments: String
}

/// 工具结果块
public struct ToolResultBlock: Sendable, Codable {
    public let toolCallId: String
    public let content: [ContentBlock]
    public let isError: Bool
}

/// 消息来源
public struct MessageSource: Sendable, Codable {
    public let kind: String
    public var plugin: String?
    
    public static let user = MessageSource(kind: "user")
    public static let plugin = MessageSource(kind: "plugin")
    public static let model = MessageSource(kind: "model")
    public static let tool = MessageSource(kind: "tool")
    
    public init(kind: String, plugin: String? = nil) {
        self.kind = kind
        self.plugin = plugin
    }
}

/// Token 使用统计
public struct TokenUsage: Sendable, Codable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}

/// 工具调用事件
public struct ToolCallEvent: Sendable, Codable {
    public let turn: Int
    public let step: Int
    public let callId: String
    public let name: String
    public let arguments: String
}

/// 工具结果事件
public struct ToolResultEvent: Sendable, Codable {
    public let turn: Int
    public let step: Int
    public let callId: String
    public let content: [ContentBlock]
    public let error: ToolError?
    public let meta: [String: AnyCodable]?
}

/// 工具错误
public struct ToolError: Sendable, Codable {
    public let name: String
    public let code: String
}

/// 请求头
public struct EpochHeader: Sendable, Codable {
    public let version: Int
    public let timestamp: Date
}

/// 请求上下文
public struct RequestContext: Sendable, Codable {
    public let provider: String
    public let model: String
    public let maxTokens: Int?
}

/// Todo 项
public struct TodoItem: Sendable, Codable {
    public let id: String
    public let content: String
    public let isCompleted: Bool
    public let priority: Int
}
