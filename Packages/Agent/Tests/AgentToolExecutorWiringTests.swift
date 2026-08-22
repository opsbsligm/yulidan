@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - 桩工具（Agent 层接线用）

struct AgentEchoTool: Tool {
    let name = "agent_echo"
    let description = "回显"
    let parameterSchema = "{}"
    let requiredParameters = ["text"]

    func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text("echo: \(args["text"] ?? "")")])
    }
}

struct AgentSlowTool: Tool {
    let name = "agent_slow"
    let description = "慢工具"
    let parameterSchema = "{}"
    let delay: TimeInterval

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        try? await Task.sleep(for: .seconds(delay))
        return ToolResult(content: [.text("slow done")])
    }
}

actor ToolEventBox {
    private(set) var events: [ToolExecEvent] = []
    func append(_ event: ToolExecEvent) {
        events.append(event)
    }
}

// MARK: - 会话工作目录下发（P0.1.5）

final class WdCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URL?
    var captured: URL? {
        lock.withLock { value }
    }

    func set(_ v: URL?) {
        lock.withLock { value = v }
    }
}

struct WdCaptureTool: Tool {
    let name = "wd_capture"
    let description = "捕获上下文工作目录"
    let parameterSchema = "{}"
    let requiredParameters: [String] = []
    let box: WdCaptureBox

    func execute(_: [String: String], context: ToolRunContext) async throws -> ToolResult {
        box.set(context.workingDirectory)
        return ToolResult(content: [.text("wd captured")])
    }
}

@Suite("AgentLoop 会话工作目录下发")
struct AgentWorkingDirectoryTests {
    @Test("workingDirectoryProvider 的值送达工具上下文")
    func providerDelivery() async throws {
        let wd = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-agent-wd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: wd, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: wd) }

        let box = WdCaptureBox()
        let registry = ToolRegistry()
        await registry.register(WdCaptureTool(box: box))
        let llm = ScriptedLLM(responses: [
            LLMResponse(model: "mock-model", content: [],
                        toolCalls: [LLM.ToolCallBlock(id: "c1", name: "wd_capture", arguments: "{}")],
                        finishReason: .toolCalls),
            textResponse("done"),
        ])
        let loop = AgentLoop(sessionID: SessionID(), llm: llm, tools: registry,
                             model: "mock-model",
                             workingDirectoryProvider: { _ in wd })
        await loop.send(UserMessage(content: [.text("捕获")]), target: .nextTurn, wakeup: true)
        let result = await loop.whenIdle()
        #expect(result.error == nil, "turn 不应报错：\(String(describing: result.error))")
        #expect(box.captured?.path == wd.path, "工具上下文应携带 provider 下发的工作目录")
    }
}

// MARK: - AgentLoop × ToolExecutor 接线测试

@Suite("AgentLoop 工具链路接线（ToolExecutor）")
struct AgentLoopToolExecutorWiringTests {
    @Test("工具调用 → 结果回填 → 最终回答（两步闭环）")
    func endToEnd() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("agent_echo", #"{"text":"hi"}"#, id: "c1"),
            textResponse("完成"),
        ])
        let registry = ToolRegistry()
        await registry.register(AgentEchoTool())
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model")
        await loop.send(UserMessage(content: [.text("用工具回显 hi")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        #expect(llm.callCount == 2)
        #expect(result.steps.count == 2)
        let results = await loop.allToolResults
        #expect(results.count == 1)
        #expect(results.first?.error == nil)
        let texts = await loop.lastResult.messages.compactMap { m in
            m.content.compactMap { block -> String? in
                if case let .text(s) = block {
                    return s
                }
                return nil
            }.joined()
        }
        #expect(texts.contains { $0.contains("完成") })
    }

    @Test("多轮嵌套：连续两次工具调用后收敛（3 步）")
    func nestedMultiRound() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("agent_echo", #"{"text":"a"}"#, id: "c1"),
            toolResponse("agent_echo", #"{"text":"b"}"#, id: "c2"),
            textResponse("两轮都完成"),
        ])
        let registry = ToolRegistry()
        await registry.register(AgentEchoTool())
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model")
        await loop.send(UserMessage(content: [.text("连续调用两次")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        #expect(llm.callCount == 3)
        #expect(result.steps.count == 3)
        let results = await loop.allToolResults
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.error == nil })
    }

    @Test("工具超时：Agent 不悬挂，错误结果回填并继续")
    func timeoutSurfacesAndContinues() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("agent_slow", "{}", id: "c1"),
            textResponse("超时后继续"),
        ])
        let registry = ToolRegistry()
        await registry.register(AgentSlowTool(delay: 5))
        let box = ToolEventBox()
        let executor = ToolExecutor(policy: .init(defaultTimeout: 0.3))
        executor.onEvent = { event in
            Task { await box.append(event) }
        }
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model", executor: executor)
        let start = Date()
        await loop.send(UserMessage(content: [.text("慢任务")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop, timeout: 4)
        #expect(result.error == nil, "工具超时应作为错误结果回填，而不是打死 Agent")
        #expect(Date().timeIntervalSince(start) < 3, "整体应在超时 + 余量内完成")
        let results = await loop.allToolResults
        #expect(results.count == 1)
        #expect(results.first?.error?.code == "timeout")
        try? await Task.sleep(for: .milliseconds(100))
        let events = await box.events
        #expect(events.contains { event in
            if case let .finished(_, _, isError) = event {
                return isError
            }
            return false
        })
    }

    @Test("未知工具：错误结果回填，Agent 继续收敛")
    func unknownToolContinues() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("no_such", "{}", id: "c1"),
            textResponse("工具不存在也收敛"),
        ])
        let registry = ToolRegistry()
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model")
        await loop.send(UserMessage(content: [.text("调用不存在的工具")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        let results = await loop.allToolResults
        #expect(results.first?.error?.code == "unknown_tool")
    }
}
