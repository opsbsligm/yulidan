import Agent
import Foundation
import LLM
import Session
import Subagent
import Testing
import Tools

// MARK: - Subagent 包薄弱分支覆盖（覆盖审计轮 11）

// MockAgent 复用 SubagentTests.swift（同测试目标，internal 可见）

/// 仅输出 reasoning 的脚本化 LLM：最终回答无 text 块、无工具调用 → AgentLoop 单步收敛
private final class ReasoningOnlyLLM: LLMProvider, @unchecked Sendable {
    let id = "reasoning-llm"
    let supportedModels = ["mock-model"]

    func request(_: LLMRequest) async throws -> LLMResponse {
        LLMResponse(model: "mock-model", content: [.reasoning("斟酌中……")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@Suite("Subagent Gap Coverage")
struct SubagentGapCoverageTests {
    /// ① slotLog 函数体：SUBAGENT_SLOT_DEBUG=1 时 acquire/release 槽位日志开启
    ///    （spawn→waitFor 全链路必过 fast-acquire 与 release-decrement 两条日志路径）
    @Test("slotLog 函数体：SUBAGENT_SLOT_DEBUG=1 → spawn 全链路槽位日志路径命中")
    func slotLogBodyWhenDebugEnabled() async {
        setenv("SUBAGENT_SLOT_DEBUG", "1", 1)
        defer { unsetenv("SUBAGENT_SLOT_DEBUG") }
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = MockAgent(delay: 0.05)
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "槽位日志", task: "全链路"))
        let state = await coordinator.waitFor(id)
        #expect(state.phase == .succeeded)
    }

    /// ② spawn_subagent：子 Agent 最终回答仅 reasoning（无文本）
    ///    → 工具回传兜底文案「子任务完成（无文本输出）」而非空串
    @Test("spawn_subagent：子 Agent 仅 reasoning 输出 → 兜底文案「子任务完成（无文本输出）」")
    func reasoningOnlySubtaskFallsBackToNoText() async throws {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let tool = SpawnSubagentTool(
            coordinator: coordinator,
            subTools: ToolRegistry(),
            model: "mock-model",
            makeLLM: { ReasoningOnlyLLM() }
        )
        let context = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let result = try await tool.execute(["task": "仅推理任务"], context: context)
        #expect(result.error == nil)
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        #expect(text == "子任务完成（无文本输出）")
    }
}
