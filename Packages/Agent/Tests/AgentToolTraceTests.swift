@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - 桩工具（轨迹回归用）

/// 超长输出工具（截断测试：3000 字符）
struct AgentLongTool: Tool {
    let name = "agent_long"
    let description = "超长输出"
    let parameterSchema = "{}"
    let requiredParameters: [String] = []

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text(String(repeating: "x", count: 3000))])
    }
}

/// 恒抛异常工具（exec_failed 路径）
struct AgentThrowTool: Tool {
    let name = "agent_throw"
    let description = "恒抛异常"
    let parameterSchema = "{}"
    let requiredParameters: [String] = []

    struct StubError: Error, LocalizedError {
        var errorDescription: String? {
            "桩异常"
        }
    }

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        throw StubError()
    }
}

// MARK: - AgentResult.toolTraces 回归

@Suite("Agent 工具轨迹（toolTraces）")
struct AgentToolTraceTests {
    @Test("成功调用：轨迹含名称/入参/ok/输出")
    func traceSuccess() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("agent_echo", #"{"text":"hi"}"#, id: "c1"),
            textResponse("完成"),
        ])
        let registry = ToolRegistry()
        await registry.register(AgentEchoTool())
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model")
        await loop.send(UserMessage(content: [.text("回显 hi")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        #expect(result.toolTraces.count == 1)
        let trace = result.toolTraces.first
        #expect(trace?.name == "agent_echo")
        #expect(trace?.arguments == #"{"text":"hi"}"#)
        #expect(trace?.ok == true)
        #expect(trace?.output == "echo: hi")
    }

    @Test("未知工具：轨迹 ok=false 且输出含错误码")
    func traceUnknownTool() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("no_such_tool", "{}"),
            textResponse("降级回答"),
        ])
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("q")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        #expect(result.toolTraces.count == 1)
        #expect(result.toolTraces.first?.ok == false)
        #expect(result.toolTraces.first?.output.contains("unknown_tool") == true)
    }

    @Test("工具抛异常：轨迹 ok=false 且输出含 exec_failed")
    func traceExecFailed() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("agent_throw", "{}", id: "c1"),
            textResponse("降级回答"),
        ])
        let registry = ToolRegistry()
        await registry.register(AgentThrowTool())
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model")
        await loop.send(UserMessage(content: [.text("q")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        #expect(result.toolTraces.count == 1)
        #expect(result.toolTraces.first?.ok == false)
        #expect(result.toolTraces.first?.output.contains("exec_failed") == true)
    }

    @Test("步数上限：轨迹按执行序累积并在终止时返回")
    func traceStepLimit() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("agent_echo", #"{"text":"a"}"#, id: "c1"),
            toolResponse("agent_echo", #"{"text":"b"}"#, id: "c2"),
        ])
        let registry = ToolRegistry()
        await registry.register(AgentEchoTool())
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model", maxSteps: 2)
        await loop.send(UserMessage(content: [.text("q")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error != nil)
        #expect(result.toolTraces.count == 2)
        #expect(result.toolTraces.map(\.id) == [0, 1])
        #expect(result.toolTraces.map(\.ok) == [true, true])
    }

    @Test("长输出截断至 2000 字符")
    func traceOutputTruncation() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("agent_long", "{}", id: "c1"),
            textResponse("完成"),
        ])
        let registry = ToolRegistry()
        await registry.register(AgentLongTool())
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: registry, model: "mock-model")
        await loop.send(UserMessage(content: [.text("q")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.toolTraces.first?.ok == true)
        #expect(result.toolTraces.first?.output.count == 2000)
    }

    @Test("traceOutput：错误场景=错误前缀+正文前 800；纯错误=仅前缀")
    func traceOutputErrorHead() {
        let long = String(repeating: "y", count: 3000)
        let withText = ToolResult(content: [.text(long)],
                                  error: ToolError(name: "t", code: "exec_failed", message: "boom"))
        let out = AgentLoop.traceOutput(from: withText)
        let head = "错误（exec_failed）：boom"
        #expect(out.hasPrefix(head))
        #expect(out.count == head.count + 1 + 800)

        let textOnly = ToolResult(content: [.text("工具 t 执行超时（30s）")],
                                  error: ToolError(name: "t", code: "timeout", message: "工具 t 执行超时（30s）"))
        let out2 = AgentLoop.traceOutput(from: textOnly)
        #expect(out2.hasPrefix("错误（timeout）："))
    }
}
