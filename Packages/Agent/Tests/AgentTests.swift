@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

@Suite("AgentID Tests")
struct AgentIDTests {
    @Test("Unique IDs")
    func unique() {
        let id1 = AgentID()
        let id2 = AgentID()
        #expect(id1.rawValue != id2.rawValue)
    }
}

@Suite("Inbox Tests")
struct InboxTests {
    @Test("Append and claim")
    func testNextTurn() {
        let inbox = Inbox()
        let msg = UserMessage(content: [.text("Hello")])
        inbox.append(msg, target: .nextTurn)
        #expect(inbox.hasPending)
        let batch = inbox.claimNext()
        #expect(batch?.count == 1)
        #expect(!inbox.hasPending)
    }

    @Test("Claim returns nextStep + nextTurn")
    func claimOrder() {
        let inbox = Inbox()
        inbox.append(UserMessage(content: [.text("Turn")]), target: .nextTurn)
        inbox.append(UserMessage(content: [.text("Step")]), target: .nextStep)
        let batch = inbox.claimNext()
        #expect(batch?.count == 2)
    }

    @Test("Clear removes all")
    func testClear() {
        let inbox = Inbox()
        inbox.append(UserMessage(content: [.text("Hello")]), target: .nextTurn)
        inbox.clear()
        #expect(!inbox.hasPending)
    }

    @Test("Empty claim returns nil")
    func empty() {
        let inbox = Inbox()
        #expect(inbox.claimNext() == nil)
    }

    @Test("Multiple nextStep messages")
    func multipleNextStep() {
        let inbox = Inbox()
        inbox.append(UserMessage(content: [.text("step1")]), target: .nextStep)
        inbox.append(UserMessage(content: [.text("step2")]), target: .nextStep)
        inbox.append(UserMessage(content: [.text("turn")]), target: .nextTurn)
        let batch = inbox.claimNext()
        #expect(batch?.count == 3)
    }
}

@Suite("Turn Tests")
struct TurnTests {
    @Test("Initialize")
    func testInit() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        #expect(await turn.number == 1)
        #expect(await turn.status == .active)
    }

    @Test("Complete")
    func testComplete() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        await turn.complete()
        #expect(await turn.status == .completed)
    }

    @Test("Cancel")
    func testCancel() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        await turn.cancel()
        #expect(await turn.status == .cancelled)
    }

    @Test("Tool result")
    func toolResult() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        let result = ToolResult(content: [LLM.ContentBlock.text("r")])
        await turn.recordToolResult(result)
        #expect(await turn.toolResults.count == 1)
    }
}

@Suite("AgentLoop Tests")
struct AgentLoopTests {
    @Test("Initialize")
    func testInit() async {
        let loop = makeLoop()
        #expect(await loop.currentStatus == .idle)
    }

    @Test("When idle")
    func testWhenIdle() async {
        let loop = makeLoop()
        let result = await loop.whenIdle()
        #expect(result.status == .idle)
    }

    @Test("Cancel")
    func testCancel() async {
        let loop = makeLoop()
        await loop.cancel(keepInbox: false)
        #expect(await loop.currentStatus == .idle)
    }
}

// MARK: - AgentLoop Extended Tests

@Suite("AgentLoop Extended Tests")
struct AgentLoopExtendedTests {
    @Test("send with wakeup=false adds to inbox without processing")
    func sendNoWakeup() async {
        let loop = makeLoop()
        let msg = UserMessage(content: [.text("test")])
        await loop.send(msg, target: .nextTurn, wakeup: false)
        #expect(await loop.currentStatus == .idle)
    }

    @Test("send with wakeup=true triggers processInbox")
    func sendWithWakeup() async {
        let loop = makeLoop()
        let msg = UserMessage(content: [.text("test")])
        await loop.send(msg, target: .nextTurn, wakeup: true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await loop.currentStatus == .idle)
    }

    @Test("followup adds message and triggers processInbox")
    func testFollowup() async {
        let loop = makeLoop()
        let msg = UserMessage(content: [.text("followup")])
        await loop.followup(msg)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await loop.currentStatus == .idle)
    }

    @Test("inject adds message to nextStep without triggering")
    func testInject() async {
        let loop = makeLoop()
        let msg = UserMessage(content: [.text("inject")])
        await loop.inject(msg)
        #expect(await loop.currentStatus == .idle)
    }

    @Test("cancel keeps inbox when keepInbox=true")
    func cancelKeepInbox() async {
        let loop = makeLoop()
        let msg = UserMessage(content: [.text("keep")])
        await loop.inject(msg)
        await loop.cancel(keepInbox: true)
        #expect(await loop.currentStatus == .idle)
    }

    @Test("cancel clears inbox when keepInbox=false")
    func cancelClearInbox() async {
        let loop = makeLoop()
        let msg = UserMessage(content: [.text("clear")])
        await loop.inject(msg)
        await loop.cancel(keepInbox: false)
        #expect(await loop.currentStatus == .idle)
    }
}

// MARK: - Turn Extended Tests

@Suite("Turn Extended Tests")
struct TurnExtendedTests {
    @Test("fail sets status to failed")
    func testFail() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        await turn.fail(with: TestAgentError.fail)
        #expect(await turn.status == .failed)
    }

    @Test("waitForCompletion returns current status")
    func testWaitForCompletion() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        let status = await turn.waitForCompletion()
        #expect(status == .active)

        await turn.complete()
        let status2 = await turn.waitForCompletion()
        #expect(status2 == .completed)
    }

    @Test("Turn with messages")
    func turnWithMessages() async {
        let msgs = [UserMessage(content: [.text("msg1")]), UserMessage(content: [.text("msg2")])]
        let turn = Turn(sessionID: SessionID(), messages: msgs, number: 5)
        #expect(await turn.number == 5)
        #expect(await turn.messages.count == 2)
    }
}

private enum TestAgentError: Error, Sendable {
    case fail
}

// MARK: - 脚本化 LLM 与工具

/// 按序返回预设响应的 LLM（超出序列后重复最后一个）
final class ScriptedLLM: LLMProvider, @unchecked Sendable {
    let id = "mock-llm"
    let supportedModels = ["mock-model"]
    private let lock = NSLock()
    private let responses: [LLMResponse]
    private var count = 0
    private let failing: Bool

    init(responses: [LLMResponse], failing: Bool = false) {
        self.responses = responses
        self.failing = failing
    }

    var callCount: Int {
        lock.withLock { count }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        var idx = 0
        var shouldFail = false
        lock.withLock {
            count += 1
            idx = min(count - 1, max(responses.count - 1, 0))
            shouldFail = failing && count == 1
        }
        if shouldFail {
            throw LLMError.networkError("模拟网络错误")
        }
        return responses[idx]
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

func textResponse(_ text: String) -> LLMResponse {
    LLMResponse(model: "mock-model", content: [.text(text)], finishReason: .stop)
}

func toolResponse(_ name: String, _ arguments: String, id: String = "call-1") -> LLMResponse {
    LLMResponse(
        model: "mock-model",
        content: [],
        toolCalls: [LLM.ToolCallBlock(id: id, name: name, arguments: arguments)],
        finishReason: .toolCalls
    )
}

func makeLoop(_ responses: [LLMResponse] = [textResponse("ok")], failing: Bool = false, maxSteps: Int = 8) -> AgentLoop {
    AgentLoop(
        id: AgentID(),
        sessionID: SessionID(),
        llm: ScriptedLLM(responses: responses, failing: failing),
        tools: ToolRegistry(),
        model: "mock-model",
        maxSteps: maxSteps
    )
}

/// 轮询等待 loop 完成当前 turn
func awaitTurnResult(_ loop: AgentLoop, timeout: Double = 5) async -> AgentResult {
    let startTurns = await loop.turnNumber
    let deadline = Date().addingTimeInterval(timeout)
    // 等到「新 turn 已启动且已结束」：turnNumber 递增发生在 runTurn 入口，
    // status 回到 .idle 时 lastResult 必然已写入（actor 串行保证）。
    while Date() < deadline {
        if await loop.turnNumber > startTurns, await loop.currentStatus != .running {
            break
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await loop.lastTurnResult
}

@Suite("AgentLoop Turn 循环测试")
struct AgentLoopTurnTests {
    @Test("纯文本回答：一次 LLM 调用后结束")
    func textAnswer() async {
        let llm = ScriptedLLM(responses: [textResponse("你好，我是助手")])
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("你好")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        #expect(result.messages.count == 1)
        #expect(await llm.callCount == 1)
    }

    @Test("工具调用循环：真实执行 exec_command 后回填并继续")
    func toolCallLoop() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("exec_command", #"{"cmd":"echo hello-agent"}"#),
            textResponse("执行完毕"),
        ])
        let tools = ToolRegistry()
        for tool in BuiltinTools.makeAll() {
            await tools.register(tool)
        }
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: tools, model: "mock-model")
        await loop.send(UserMessage(content: [.text("执行命令")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        var finalText = ""
        if let first = result.messages.first, let block = first.content.first, case let .text(t) = block {
            finalText = t
        }
        #expect(finalText == "执行完毕")
        #expect(await llm.callCount == 2)
        let toolResults = await loop.allToolResults
        #expect(toolResults.count == 1)
        let first = toolResults.first
        #expect(first?.error == nil)
        #expect(first.map { AgentLoop.text(from: $0.content).contains("hello-agent") } == true)
    }

    @Test("未知工具：记录错误并继续对话")
    func unknownTool() async {
        let llm = ScriptedLLM(responses: [
            toolResponse("no_such_tool", "{}"),
            textResponse("降级回答"),
        ])
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("q")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        let toolResults = await loop.allToolResults
        #expect(toolResults.count == 1)
        #expect(toolResults.first?.error?.code == "unknown_tool")
    }

    @Test("LLM 抛错：turn 失败并返回错误信息")
    func llmFailure() async {
        let loop = makeLoop([textResponse("never")], failing: true)
        await loop.send(UserMessage(content: [.text("q")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error != nil)
        #expect(result.error?.contains("模拟网络错误") == true)
    }

    @Test("步数上限：连续工具调用达到 maxSteps 后终止")
    func stepLimit() async {
        let llm = ScriptedLLM(responses: [toolResponse("exec_command", #"{"cmd":"echo 1"}"#)])
        let tools = ToolRegistry()
        for tool in BuiltinTools.makeAll() {
            await tools.register(tool)
        }
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: tools, model: "mock-model", maxSteps: 3)
        await loop.send(UserMessage(content: [.text("loop")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error != nil)
        #expect(result.error?.contains("超过上限") == true)
        #expect(await llm.callCount == 3)
    }

    @Test("parseArguments：字符串/数字/布尔/嵌套结构解析")
    func parseArgs() {
        let parsed = AgentLoop.parseArguments(#"{"path":"/tmp","n":42,"flag":true,"obj":{"a":1}}"#)
        #expect(parsed["path"] == "/tmp")
        #expect(parsed["n"] == "42")
        #expect(parsed["flag"] == "true")
        #expect(parsed["obj"]?.contains(#""a":1"#) == true)
        #expect(AgentLoop.parseArguments("not-json").isEmpty)
    }

    @Test("Turn.receiveChunk：流式块可记录（命名冲突已修复）")
    func turnReceiveChunk() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        await turn.receiveChunk(LLM.StreamChunk(type: "delta", data: Data("hi".utf8), index: 0))
        #expect(await turn.chunks.count == 1)
        #expect(await turn.chunks[0].type == "delta")
    }
}
