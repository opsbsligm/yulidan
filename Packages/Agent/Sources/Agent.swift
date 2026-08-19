import Foundation
import LLM
import ServiceContainer
import Session
import Tools

public protocol Agent: Sendable {
    var id: AgentID { get }
    var sessionID: SessionID { get }
    var status: AgentStatus { get }
    func send(_ message: UserMessage, target: InboxTarget, wakeup: Bool) async
    func followup(_ message: UserMessage) async
    func inject(_ message: UserMessage) async
    func cancel(keepInbox: Bool) async
    func whenIdle() async -> AgentResult
}

public struct AgentID: Sendable, Hashable, Codable {
    public let rawValue: UUID
    public init() {
        rawValue = UUID()
    }
}

public enum AgentStatus: String, Sendable, Codable {
    case idle, running
}

public enum InboxTarget: String, Sendable, Codable {
    case nextTurn, nextStep
}

/// 工具执行轨迹（UI 展示用：工具名 / 入参 / 输出摘要 / 成败）
public struct ToolTraceEntry: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let arguments: String
    /// 输出摘要（截断至 2000 字符；错误时含错误信息）
    public let output: String
    public let ok: Bool

    public init(id: Int, name: String, arguments: String, output: String, ok: Bool) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.output = output
        self.ok = ok
    }
}

public struct AgentResult: Sendable {
    public let status: AgentStatus
    public let messages: [AssistantMessage]
    public let error: String?
    /// 本 turn 的全部助手消息（含中间工具调用步骤，按步序；最终回答在最后）
    public let steps: [AssistantMessage]
    /// 本 turn 的工具执行轨迹（按执行序；UI 折叠展示）
    public let toolTraces: [ToolTraceEntry]

    public init(status: AgentStatus, messages: [AssistantMessage] = [], error: String? = nil,
                steps: [AssistantMessage] = [], toolTraces: [ToolTraceEntry] = []) {
        self.status = status
        self.messages = messages
        self.error = error
        self.steps = steps
        self.toolTraces = toolTraces
    }
}
