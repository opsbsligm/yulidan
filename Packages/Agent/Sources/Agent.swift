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

public struct AgentResult: Sendable {
    public let status: AgentStatus
    public let messages: [AssistantMessage]
    public let error: String?

    public init(status: AgentStatus, messages: [AssistantMessage] = [], error: String? = nil) {
        self.status = status
        self.messages = messages
        self.error = error
    }
}
