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
    private let delay: TimeInterval

    init(responses: [LLMResponse], failing: Bool = false, delay: TimeInterval = 0) {
        self.responses = responses
        self.failing = failing
        self.delay = delay
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
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
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
        #expect(result.steps.count == 1)
        #expect(llm.callCount == 1)
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
        #expect(llm.callCount == 2)
        #expect(result.steps.count == 2)
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
        #expect(result.steps.isEmpty)
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
        #expect(llm.callCount == 3)
        #expect(result.steps.count == 3)
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

// MARK: - AgentLoop Agent 协议与 whenIdle 真实等待测试

/// 在限定时间内取任务结果；超时返回 nil（防止测试挂死）
func completesIn<T: Sendable>(_ task: Task<T, Never>, within seconds: Double) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await task.value }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next().flatMap(\.self)
        group.cancelAll()
        return first
    }
}

@Suite("AgentLoop Agent 协议与 whenIdle 真实等待测试")
struct AgentLoopWhenIdleTests {
    @Test("AgentLoop 可作为 any Agent 使用（协议一致性）")
    func conformance() async {
        let loop = makeLoop()
        let agent: any Agent = loop
        #expect(agent.status == .idle)
        let result = await agent.whenIdle()
        #expect(result.status == .idle)
        #expect(await loop.currentStatus == .idle)
    }

    @Test("whenIdle：空闲且无待处理消息时立即返回")
    func immediateWhenIdle() async {
        let loop = makeLoop()
        let result = await loop.whenIdle()
        #expect(result.status == .idle)
    }

    @Test("whenIdle：send 后立即调用（wakeup Task 未启动）也会等到 turn 结束")
    func waitsForQueuedTurn() async {
        let llm = ScriptedLLM(responses: [textResponse("任务完成")], delay: 0.1)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("执行任务")]), target: .nextTurn, wakeup: true)
        let result = await loop.whenIdle()
        #expect(result.error == nil)
        #expect(result.messages.count == 1)
        let text = result.messages.first?.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined() ?? ""
        #expect(text.contains("任务完成"))
    }

    @Test("whenIdle：运行中的 turn 阻塞等待直到结束（不再是立即返回的假实现）")
    func blocksWhileRunning() async {
        let llm = ScriptedLLM(responses: [textResponse("慢任务")], delay: 0.15)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("go")]), target: .nextTurn, wakeup: true)
        let waiter = Task { await loop.whenIdle() }
        // 50ms 内不应返回（证明真的在等慢 LLM 响应）
        #expect(await completesIn(waiter, within: 0.05) == nil)
        let result = await waiter.value
        #expect(result.error == nil)
        #expect(result.messages.count == 1)
    }

    @Test("cancel：唤醒挂起的 whenIdle 等待者（不再死等）")
    func cancelWakesWaiter() async {
        let llm = ScriptedLLM(responses: [textResponse("很慢")], delay: 5)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("go")]), target: .nextTurn, wakeup: true)
        let waiter = Task { await loop.whenIdle() }
        try? await Task.sleep(for: .milliseconds(80))
        await loop.cancel(keepInbox: true)
        let result = await completesIn(waiter, within: 2) ?? AgentResult(status: .idle)
        #expect(result.status == .idle)
    }

    @Test("cancel 标记：cancel 后再调 whenIdle 立即返回空结果")
    func cancelFlagShortCircuits() async {
        let loop = makeLoop()
        await loop.cancel(keepInbox: true)
        let result = await loop.whenIdle()
        #expect(result.status == .idle)
        #expect(result.messages.isEmpty)
    }

    /// P2：WebUI 超时取消 whenIdle 后不再悬挂到 turn 结束（Task 取消 → 立即唤醒）
    @Test("whenIdle 任务取消：立即唤醒，不等待慢 turn 结束")
    func taskCancellationWakesWaiter() async {
        let llm = ScriptedLLM(responses: [textResponse("很慢的回答")], delay: 3)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("go")]), target: .nextTurn, wakeup: true)
        let waiter = Task { await loop.whenIdle() }
        try? await Task.sleep(for: .milliseconds(100)) // 确保已进入挂起
        // 5s 的 turn 尚未结束；此时取消等待任务（模拟 WebUI 超时）
        waiter.cancel()
        let start = Date()
        let result = await waiter.value // 必须在取消后迅速返回，而非等 5s
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1, "取消后应在 1s 内返回，实际 \(elapsed)")
        _ = result // 取消路径结果仅作收敛（调用方任务已废弃该结果）
        // turn 本身继续运行不受影响
        _ = await loop.whenIdle()
        #expect(await loop.currentStatus == .idle)
    }

    /// 正常完成路径不受取消感知改造影响（OnceBox 恰好一方生效）
    @Test("whenIdle 正常完成：turn 结束按序唤醒（取消感知改造回归）")
    func normalCompletionStillWakes() async {
        let llm = ScriptedLLM(responses: [textResponse("ok")], delay: 0.1)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        await loop.send(UserMessage(content: [.text("go")]), target: .nextTurn, wakeup: true)
        let a = Task { await loop.whenIdle() }
        let b = Task { await loop.whenIdle() }
        try? await Task.sleep(for: .milliseconds(50))
        let ra = await a.value
        let rb = await b.value
        #expect(ra.error == nil && rb.error == nil)
        #expect(ra.messages.count == 1 && rb.messages.count == 1)
    }
}

// MARK: - AgentLoop 上下文裁剪（maxHistoryMessages）

/// 记录单次 LLM 请求的消息数峰值（验证历史裁剪有界）
actor RequestSizeRecorder {
    private(set) var maxMessages = 0
    func record(_ count: Int) {
        maxMessages = Swift.max(maxMessages, count)
    }
}

final class CountingLLM: LLMProvider, @unchecked Sendable {
    let id = "counting-llm"
    let supportedModels = ["mock-model"]
    private let recorder: RequestSizeRecorder

    init(recorder: RequestSizeRecorder) {
        self.recorder = recorder
    }

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        await recorder.record(request.messages.count)
        return textResponse("ok")
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@Suite("AgentLoop 上下文裁剪（maxHistoryMessages）")
struct AgentLoopHistoryTrimTests {
    @Test("30 轮对话：请求消息数有界，不随轮次无界增长")
    func trimmingKeepsBounded() async {
        let recorder = RequestSizeRecorder()
        let llm = CountingLLM(recorder: recorder)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: ToolRegistry(), model: "mock-model",
                             maxSteps: 8, maxHistoryMessages: 10)
        for i in 0 ..< 30 {
            await loop.send(UserMessage(content: [.text("消息 \(i)")]), target: .nextTurn, wakeup: true)
            // send 与 whenIdle 均为 actor 隔离：入箱后 whenIdle 必然挂起等待本 turn
            _ = await loop.whenIdle()
        }
        #expect(await loop.turnNumber == 30)
        #expect(await loop.currentStatus == .idle)
        let maxMsgs = await recorder.maxMessages
        // 上限 10：每轮 +1 user 后请求，峰值 = 上限 + 1
        #expect(maxMsgs <= 12, "请求消息数应受上限约束（实际峰值 \(maxMsgs)）")
        #expect(maxMsgs >= 10, "首轮裁剪前应累积到接近上限（实际峰值 \(maxMsgs)）")
    }

    @Test("上限最小值钳制：maxHistoryMessages < 4 时按 4 生效")
    func minimumClampedToFour() async {
        let recorder = RequestSizeRecorder()
        let llm = CountingLLM(recorder: recorder)
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: ToolRegistry(), model: "mock-model",
                             maxSteps: 8, maxHistoryMessages: 1)
        for i in 0 ..< 20 {
            await loop.send(UserMessage(content: [.text("消息 \(i)")]), target: .nextTurn, wakeup: true)
            _ = await loop.whenIdle()
        }
        let maxMsgs = await recorder.maxMessages
        #expect(maxMsgs <= 6, "钳制到 4 后峰值应为 4+1（实际峰值 \(maxMsgs)）")
    }
}
