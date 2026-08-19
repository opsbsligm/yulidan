@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - AgentLoop history 种子注入（前端阶段2：主聊天路径复用既有上下文）

/// 记录每次请求消息数的 LLM（用于断言种子历史被带入首轮请求）
private final class RecordingLLM: LLMProvider, @unchecked Sendable {
    let id = "rec-llm"
    let supportedModels = ["mock-model"]
    private let lock = NSLock()
    private var requestMessages: [[LLM.Message]] = []
    private let responses: [LLMResponse]

    init(responses: [LLMResponse]) {
        self.responses = responses
    }

    var requests: [[LLM.Message]] {
        lock.withLock { requestMessages }
    }

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        var idx = 0
        lock.withLock {
            idx = min(requestMessages.count, max(responses.count - 1, 0))
            requestMessages.append(request.messages)
        }
        return responses[idx]
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@Suite("AgentLoop history 种子", .serialized)
struct AgentHistorySeedTests {
    private func seed() -> [LLM.Message] {
        [
            LLM.Message(role: .user, content: [.text("历史问题")]),
            LLM.Message(role: .assistant, content: [.text("历史回答")]),
        ]
    }

    @Test("种子历史出现在首轮请求且位于新用户消息之前")
    func seedPrecedesNewUserMessage() async {
        let llm = RecordingLLM(responses: [
            LLMResponse(model: "mock-model", content: [.text("ok")], finishReason: .stop),
        ])
        let agent = AgentLoop(
            sessionID: SessionID(),
            llm: llm,
            tools: ToolRegistry(),
            model: "mock-model",
            history: seed()
        )
        await agent.followup(UserMessage(content: [.text("新问题")]))
        _ = await agent.whenIdle()

        let req = llm.requests.first
        #expect(req != nil)
        let texts = (req ?? []).compactMap { m -> String? in
            m.content.compactMap { block -> String? in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.joined()
        }
        #expect(texts.contains("历史问题"))
        #expect(texts.contains("新问题"))
        if let hIdx = texts.firstIndex(of: "历史问题"), let nIdx = texts.firstIndex(of: "新问题") {
            #expect(hIdx < nIdx, "种子历史应先于新用户消息")
        }
    }

    @Test("空种子不改变行为")
    func emptySeedIsNoop() async {
        let llm = RecordingLLM(responses: [
            LLMResponse(model: "mock-model", content: [.text("ok")], finishReason: .stop),
        ])
        let agent = AgentLoop(
            sessionID: SessionID(),
            llm: llm,
            tools: ToolRegistry(),
            model: "mock-model",
            history: []
        )
        await agent.followup(UserMessage(content: [.text("hi")]))
        _ = await agent.whenIdle()
        let req = llm.requests.first
        #expect(req?.count == 1)
    }

    @Test("超长种子按上限裁剪")
    func oversizedSeedTrimmed() async {
        var big: [LLM.Message] = []
        for i in 0 ..< 300 {
            big.append(LLM.Message(role: .user, content: [.text("m\(i)")]))
        }
        let llm = RecordingLLM(responses: [
            LLMResponse(model: "mock-model", content: [.text("ok")], finishReason: .stop),
        ])
        let agent = AgentLoop(
            sessionID: SessionID(),
            llm: llm,
            tools: ToolRegistry(),
            model: "mock-model",
            maxHistoryMessages: 100,
            history: big
        )
        await agent.followup(UserMessage(content: [.text("now")]))
        _ = await agent.whenIdle()
        let req = llm.requests.first
        // 100 裁剪 + 1 新消息 = 101
        #expect(req?.count == 101)
    }
}
