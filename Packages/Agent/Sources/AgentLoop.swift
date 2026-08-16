import Foundation
import ServiceContainer
import Session
import LLM
import Tools

/// Agent Loop — 驱动 Agent 对话循环
actor AgentLoop {
    let id: AgentID
    let sessionID: SessionID
    private var status: AgentStatus = .idle
    private var inbox: Inbox
    
    init(id: AgentID = AgentID(), sessionID: SessionID) {
        self.id = id
        self.sessionID = sessionID
        self.inbox = Inbox()
    }
    
    var currentStatus: AgentStatus { status }
    
    func send(_ message: UserMessage, target: InboxTarget, wakeup: Bool) {
        inbox.append(message, target: target)
        if wakeup {
            Task { [weak self] in await self?.processInbox() }
        }
    }
    
    func followup(_ message: UserMessage) {
        inbox.append(message, target: .nextTurn)
        Task { [weak self] in await self?.processInbox() }
    }
    
    func inject(_ message: UserMessage) {
        inbox.append(message, target: .nextStep)
    }
    
    func cancel(keepInbox: Bool) {
        if !keepInbox { inbox.clear() }
        status = .idle
    }
    
    func whenIdle() async -> AgentResult {
        AgentResult(status: status)
    }
    
    private func processInbox() async {
        guard status == .idle else { return }
        status = .running
        
        while let batch = inbox.claimNext() {
            // TODO: 实现完整的 turn 循环
            _ = batch
        }
        
        status = .idle
    }
}
