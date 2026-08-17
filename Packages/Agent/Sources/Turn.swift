import Foundation
import LLM
import Session
import Tools

actor Turn {
    let number: Int
    let sessionID: SessionID
    var status: TurnStatus = .active
    var messages: [UserMessage]
    var chunks: [LLM.StreamChunk] = []
    var toolCalls: [ToolCall]?
    var toolResults: [ToolResult] = []

    init(sessionID: SessionID, messages: [UserMessage], number: Int = 1) {
        self.sessionID = sessionID
        self.messages = messages
        self.number = number
    }

    func receiveChunk(_ chunk: LLM.StreamChunk) {
        chunks.append(chunk)
    }

    func recordToolResult(_ result: ToolResult) {
        toolResults.append(result)
    }

    func complete() {
        status = .completed
    }

    func fail(with _: Error) {
        status = .failed
    }

    func cancel() {
        status = .cancelled
    }

    func waitForCompletion() async -> TurnStatus {
        status
    }
}

enum TurnStatus: Sendable {
    case active, completed, failed, cancelled
}
