@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - 请求参数传播（maxTokens / thinkingLevel 从配置到达 wire 请求）

// 背景：P0 报障「最大 Token 数太低」实锤了滑块此前从未下发 wire（AgentLoop 构造 LLMRequest 漏传）

@Suite("AgentLoop 请求参数传播")
struct RequestParamsPropagationTests {
    /// 捕获每次请求的 maxTokens / thinkingLevel
    private final class CapturingLLM: LLMProvider, @unchecked Sendable {
        let id = "params-capturing"
        let supportedModels = ["mock-model"]
        let profile = ProviderProfile.mock
        private let lock = NSLock()
        private var lastMaxTokensValue: Int?
        private var lastThinkingValue: LLM.ThinkingLevel?

        var lastMaxTokens: Int? {
            lock.withLock { lastMaxTokensValue }
        }

        var lastThinking: LLM.ThinkingLevel? {
            lock.withLock { lastThinkingValue }
        }

        func request(_ request: LLMRequest) async throws -> LLMResponse {
            lock.withLock {
                lastMaxTokensValue = request.maxTokens
                lastThinkingValue = request.thinkingLevel
            }
            return textResponse("ok")
        }

        func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    @Test("init 注入：maxTokens / thinkingLevel 到达 LLMRequest")
    func initParamsReachRequest() async {
        let llm = CapturingLLM()
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(),
                             model: "mock-model", maxTokens: 262_144, thinkingLevel: .high)
        await loop.send(UserMessage(content: [.text("hi")]), target: .nextTurn, wakeup: true)
        _ = await awaitTurnResult(loop)
        #expect(llm.lastMaxTokens == 262_144, "maxTokens 未到达 LLMRequest（配置项是摆设）")
        #expect(llm.lastThinking == .high, "thinkingLevel 未到达 LLMRequest")
    }

    @Test("setTurnContext 跨轮更新：新参数即时生效且历史保留")
    func turnContextUpdateAppliesNextTurn() async {
        let llm = CapturingLLM()
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(),
                             model: "mock-model", maxTokens: 4096, thinkingLevel: .off)
        await loop.send(UserMessage(content: [.text("第一轮")]), target: .nextTurn, wakeup: true)
        _ = await awaitTurnResult(loop)
        #expect(llm.lastMaxTokens == 4096)
        #expect(llm.lastThinking == .off)

        // 跨轮更新（模拟用户改配置）→ 下一轮即生效
        await loop.setTurnContext(model: "mock-model", systemPrompt: nil, maxTokens: 1_048_576, thinkingLevel: .medium)
        await loop.send(UserMessage(content: [.text("第二轮")]), target: .nextTurn, wakeup: true)
        _ = await awaitTurnResult(loop)
        #expect(llm.lastMaxTokens == 1_048_576, "setTurnContext 后 maxTokens 未生效")
        #expect(llm.lastThinking == .medium, "setTurnContext 后 thinkingLevel 未生效")
    }

    @Test("缺省 nil：请求不带 maxTokens / thinkingLevel（不强制下发）")
    func nilDefaultsSendNothing() async {
        let llm = CapturingLLM()
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(),
                             model: "mock-model")
        await loop.send(UserMessage(content: [.text("hi")]), target: .nextTurn, wakeup: true)
        _ = await awaitTurnResult(loop)
        #expect(llm.lastMaxTokens == nil)
        #expect(llm.lastThinking == nil)
    }
}
