@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - 能力门控（P2：provider 画像决定 tools 是否下发）

@Suite("AgentLoop Provider 能力门控")
struct ProviderGatingTests {
    /// 捕获每次请求 tools 的脚本 LLM，profile 可覆写
    private final class CapturingLLM: LLMProvider, @unchecked Sendable {
        let id = "capturing-llm"
        let supportedModels = ["mock-model"]
        let profile: ProviderProfile
        private let lock = NSLock()
        private var lastToolsCount: Int?

        init(profile: ProviderProfile) {
            self.profile = profile
        }

        var lastTools: Int? {
            lock.withLock { lastToolsCount }
        }

        func request(_ request: LLMRequest) async throws -> LLMResponse {
            lock.withLock { lastToolsCount = request.tools?.count }
            return textResponse("ok")
        }

        func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    @Test("画像不支持工具调用：请求不带 tools")
    func toolsWithheldWhenUnsupported() async {
        let llm = CapturingLLM(profile: .local)
        let tools = ToolRegistry()
        for tool in BuiltinTools.makeAll() {
            await tools.register(tool)
        }
        let schemas = await tools.schemas()
        #expect(!schemas.isEmpty)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: tools, model: "mock-model")
        await loop.send(UserMessage(content: [.text("你好")]), target: .nextTurn, wakeup: true)
        _ = await awaitTurnResult(loop)
        #expect(llm.lastTools == nil, "不支持工具调用的画像不应下发 tools")
    }

    @Test("画像支持工具调用：请求携带全部工具 schema")
    func toolsForwardedWhenSupported() async {
        let llm = CapturingLLM(profile: .mock)
        let tools = ToolRegistry()
        for tool in BuiltinTools.makeAll() {
            await tools.register(tool)
        }
        let schemaCount = await tools.schemas().count
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: tools, model: "mock-model")
        await loop.send(UserMessage(content: [.text("你好")]), target: .nextTurn, wakeup: true)
        _ = await awaitTurnResult(loop)
        #expect(llm.lastTools == schemaCount)
    }
}
