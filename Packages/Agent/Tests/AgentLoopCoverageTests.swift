@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - AgentLoop 内部缝覆盖加固

//
// 静态转换/解析函数（convertBlock/sessionBlock/parseArguments/traceOutput）直测；
// runTurn 集成场景：步前取消收敛 / URLError.cancelled 中性收敛 /
// 助手历史 toolCall 按 id 去重 / trimHistory 孤立 tool 结果丢弃 / 工具进度 chunk 上报。

// MARK: - 测试替身

/// 无副作用回显工具
private final class EchoTool: Tool, @unchecked Sendable {
    let name = "echo"
    let description = "echo"
    let parameterSchema = "{}"

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text("echoed")])
    }
}

/// 上报两次进度 chunk 的工具
private final class ChunkyTool: Tool, @unchecked Sendable {
    let name = "chunky"
    let description = "chunky"
    let parameterSchema = "{}"
    private let lock = NSLock()
    private var emitted = 0

    var emittedCount: Int {
        lock.withLock { emitted }
    }

    func execute(_: [String: String], context: ToolRunContext) async throws -> ToolResult {
        context.onChunk?("progress p1")
        context.onChunk?("progress p2")
        lock.withLock { emitted += 1 }
        return ToolResult(content: [.text("chunky done")])
    }
}

/// 忽略取消的慢工具（try? 吞掉 CancellationError，模拟不可协作取消的第三方工具）
private final class StubbornTool: Tool, @unchecked Sendable {
    let name = "stubborn"
    let description = "stubborn"
    let parameterSchema = "{}"
    private let lock = NSLock()
    private var startedFlag = false

    var isStarted: Bool {
        lock.withLock { startedFlag }
    }

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        lock.withLock { startedFlag = true }
        try? await Task.sleep(for: .milliseconds(400))
        return ToolResult(content: [.text("stubborn done")])
    }
}

/// 按脚本返回响应的 provider（超出脚本后恒返最终回答；捕获每次请求的 wire 历史）
private final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    let id = "scripted"
    let supportedModels = ["m"]
    private let lock = NSLock()
    private let script: [@Sendable () -> LLMResponse]
    private var count = 0
    private var histories: [[LLM.Message]] = []

    init(script: [@Sendable () -> LLMResponse]) {
        self.script = script
    }

    var requestCount: Int {
        lock.withLock { count }
    }

    var capturedHistories: [[LLM.Message]] {
        lock.withLock { histories }
    }

    func request(_ req: LLMRequest) async throws -> LLMResponse {
        var index = 0
        lock.withLock {
            histories.append(req.messages)
            index = count
            count += 1
        }
        if index < script.count {
            return script[index]()
        }
        return LLMResponse(model: "m", content: [.text("final")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// 恒抛指定错误的 provider
private final class ThrowProvider: LLMProvider, @unchecked Sendable {
    let id = "throwing"
    let supportedModels = ["m"]
    private let failure: Error
    private let lock = NSLock()
    private var requestCountValue = 0

    var requestCount: Int {
        lock.withLock { requestCountValue }
    }

    init(_ error: Error) {
        failure = error
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        lock.withLock { requestCountValue += 1 }
        throw failure
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// 有界等待条件成立（防测试悬挂）
private func waitFor(_ what: @Sendable () async -> Bool, seconds: Double = 10) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await what() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await what()
}

// MARK: - 静态转换 / 解析直测

@Suite("AgentLoop 静态转换", .serialized)
struct AgentLoopConversionTests {
    @Test("convertBlock：Session 五类块逐一映射到 LLM")
    func convertBlockAllCases() {
        guard case let .text(t) = AgentLoop.convertBlock(.text("t")) else {
            Issue.record("text case"); return
        }
        #expect(t == "t")
        guard case let .reasoning(r) = AgentLoop.convertBlock(.reasoning("r")) else {
            Issue.record("reasoning case"); return
        }
        #expect(r == "r")
        guard case let .image(img) = AgentLoop.convertBlock(
            .image(Session.ImageBlock(mimeType: "image/png", data: Data([9]), width: 4, height: 5))
        ) else {
            Issue.record("image case"); return
        }
        #expect(img.mimeType == "image/png")
        #expect(img.data == Data([9]))
        #expect(img.width == 4)
        #expect(img.height == 5)
        guard case let .toolCall(tc) = AgentLoop.convertBlock(
            .toolCall(Session.ToolCallBlock(id: "c1", name: "echo", arguments: "{}"))
        ) else {
            Issue.record("toolCall case"); return
        }
        #expect(tc.id == "c1")
        #expect(tc.name == "echo")
        guard case let .toolResult(tr) = AgentLoop.convertBlock(
            .toolResult(Session.ToolResultBlock(toolCallId: "c1", content: [.text("done"), .reasoning("rr")],
                                                isError: true))
        ) else {
            Issue.record("toolResult case"); return
        }
        #expect(tr.toolCallId == "c1")
        #expect(tr.isError == true)
        #expect(tr.content.count == 2)
    }

    @Test("sessionBlock：LLM 五类块反向映射到 Session")
    func sessionBlockAllCases() {
        guard case let .text(t) = AgentLoop.sessionBlock(from: .text("t")) else {
            Issue.record("text case"); return
        }
        #expect(t == "t")
        guard case let .reasoning(r) = AgentLoop.sessionBlock(from: .reasoning("r")) else {
            Issue.record("reasoning case"); return
        }
        #expect(r == "r")
        guard case let .image(img) = AgentLoop.sessionBlock(
            from: .image(LLM.ImageBlock(mimeType: "image/png", data: Data([7]), width: 3, height: 4))
        ) else {
            Issue.record("image case"); return
        }
        #expect(img.mimeType == "image/png")
        #expect(img.data == Data([7]))
        #expect(img.width == 3)
        #expect(img.height == 4)
        guard case let .toolCall(tc) = AgentLoop.sessionBlock(
            from: .toolCall(LLM.ToolCallBlock(id: "c9", name: "nope", arguments: "{}"))
        ) else {
            Issue.record("toolCall case"); return
        }
        #expect(tc.id == "c9")
        guard case let .toolResult(tr) = AgentLoop.sessionBlock(
            from: .toolResult(LLM.ToolResultBlock(toolCallId: "c9", content: [.text("x")], isError: false))
        ) else {
            Issue.record("toolResult case"); return
        }
        #expect(tr.toolCallId == "c9")
        #expect(tr.isError == false)
        #expect(tr.content.count == 1)
    }

    @Test("parseArguments：string/number/bool 直映、array/object JSON 化、null 兜底 describe")
    func parseArgumentsValueTypes() {
        let args = AgentLoop.parseArguments(#"{"s":"x","n":42,"b":true,"arr":[1,2],"obj":{"k":"v"},"n2":null}"#)
        #expect(args["s"] == "x")
        #expect(args["n"] == "42")
        #expect(args["b"] == "true")
        #expect(args["arr"] == "[1,2]")
        #expect(args["obj"]?.contains("\"k\"") == true)
        #expect(args["obj"]?.contains("\"v\"") == true)
        #expect(args["n2"] == "<null>")
        #expect(AgentLoop.parseArguments("not json").isEmpty)
        #expect(AgentLoop.parseArguments("[]").isEmpty)
    }

    @Test("traceOutput：非文本块忽略、错误头优先")
    func traceOutputSemantics() {
        let rich = ToolResult(content: [.image(LLM.ImageBlock(mimeType: "image/png", data: Data([1]))),
                                        .text("ok"), .reasoning("think")])
        #expect(AgentLoop.traceOutput(from: rich) == "ok")
        let failed = ToolResult(content: [.text("partial")],
                                error: ToolError(name: "t", code: "boom", message: "炸了"))
        let out = AgentLoop.traceOutput(from: failed)
        #expect(out.hasPrefix("错误（boom）：炸了"))
        #expect(out.contains("partial"))
    }

    @Test("AgentError.unknownTool 描述")
    func unknownToolDescription() {
        let err: AgentError = .unknownTool("nope")
        #expect(err.errorDescription == "未知工具：nope")
    }
}

// MARK: - runTurn 集成：取消收敛 / 去重 / 裁剪 / 进度 chunk

@Suite("AgentLoop runTurn 覆盖缝", .serialized)
struct AgentLoopRunCoverageTests {
    @Test("URLError.cancelled：在途请求取消 → 中性收敛无错误消息")
    func urlCancelledConvergesNeutrally() async {
        let provider = ThrowProvider(URLError(.cancelled))
        let loop = AgentLoop(sessionID: SessionID(), llm: provider,
                             tools: ToolRegistry(), model: "m")
        await loop.followup(UserMessage(content: [.text("q")]))
        let attempted = await waitFor { provider.requestCount >= 1 }
        #expect(attempted, "请求应已发起")
        let settled = await waitFor { await loop.currentStatus == .idle }
        #expect(settled)
        let result = await loop.lastTurnResult
        #expect(result.error == nil, "取消语义错误必须中性收敛")
        #expect(result.messages.isEmpty, "不得产生最终回答")
    }

    @Test("工具执行期间取消（工具忽略取消）：下一步步前检查命中，不再发起 LLM 请求")
    func cancelCheckedBeforeNextStep() async {
        let tool = StubbornTool()
        let registry = ToolRegistry()
        await registry.register(tool)
        let provider = ScriptedProvider(script: [
            {
                LLMResponse(model: "m", content: [.text("")],
                            toolCalls: [LLM.ToolCallBlock(id: "c1", name: "stubborn", arguments: "{}")],
                            finishReason: .stop)
            },
            {
                LLMResponse(model: "m", content: [.text("should-not-arrive")], finishReason: .stop)
            },
        ])
        let loop = AgentLoop(sessionID: SessionID(), llm: provider, tools: registry, model: "m")
        await loop.followup(UserMessage(content: [.text("go")]))
        let started = await waitFor { tool.isStarted }
        #expect(started, "工具应已开始执行")
        await loop.cancel(keepInbox: false)
        let settled = await waitFor { await loop.currentStatus == .idle }
        #expect(settled)
        #expect(provider.requestCount == 1, "取消后不得发起第二次 LLM 请求")
        let result = await loop.lastTurnResult
        #expect(result.error == nil)
    }

    @Test("助手历史：content 与 toolCalls 数组重复块按 id 去重回填 wire")
    func assistantHistoryDedupsToolCalls() async {
        let registry = ToolRegistry()
        await registry.register(EchoTool())
        let dupCall = LLM.ToolCallBlock(id: "c1", name: "echo", arguments: "{}")
        let provider = ScriptedProvider(script: [
            {
                LLMResponse(model: "m",
                            content: [.text("thinking"), .toolCall(dupCall)],
                            toolCalls: [dupCall],
                            finishReason: .stop)
            },
            {
                LLMResponse(model: "m", content: [.text("final")], finishReason: .stop)
            },
        ])
        let loop = AgentLoop(sessionID: SessionID(), llm: provider, tools: registry, model: "m")
        await loop.followup(UserMessage(content: [.text("q")]))
        let requested = await waitFor { provider.requestCount >= 2 }
        #expect(requested, "应发起两次 LLM 请求")
        let settled = await waitFor { await loop.currentStatus == .idle }
        #expect(settled)
        #expect(provider.requestCount == 2)
        let histories = provider.capturedHistories
        guard histories.count >= 2 else {
            Issue.record("应捕获两次请求历史"); return
        }
        let second = histories[1]
        guard let assistant = second.first(where: { $0.role == .assistant }) else {
            Issue.record("第二次请求应携带 assistant 历史消息"); return
        }
        let callIDs = assistant.content.compactMap { block -> String? in
            if case let .toolCall(tc) = block {
                return tc.id
            }
            return nil
        }
        #expect(callIDs == ["c1"], "重复 toolCall 必须按 id 去重")
        // 步骤消息同样去重（makeStepMessage 同契约）
        let result = await loop.lastTurnResult
        let stepCalls = result.steps.first?.content.compactMap { block -> String? in
            if case let .toolCall(tc) = block {
                return tc.id
            }
            return nil
        }
        #expect(stepCalls == ["c1"])
    }

    @Test("trimHistory：队首孤立 tool 结果被丢弃直到安全边界")
    func trimHistoryDropsOrphanToolResult() async {
        let registry = ToolRegistry()
        await registry.register(EchoTool())
        let provider = ScriptedProvider(script: [
            {
                LLMResponse(model: "m", content: [.text("")],
                            toolCalls: [LLM.ToolCallBlock(id: "c1", name: "echo", arguments: "{}")],
                            finishReason: .stop)
            },
            {
                LLMResponse(model: "m", content: [.text("final")], finishReason: .stop)
            },
        ])
        // max=2：最终 [u, a1, t1, a2] → suffix(2) = [t1, a2] → t1 为 tool → dropFirst → [a2]
        let loop = AgentLoop(sessionID: SessionID(), llm: provider, tools: registry, model: "m",
                             maxHistoryMessages: 2)
        await loop.followup(UserMessage(content: [.text("q")]))
        let requested = await waitFor { provider.requestCount >= 2 }
        #expect(requested, "应发起两次 LLM 请求")
        let settled = await waitFor { await loop.currentStatus == .idle }
        #expect(settled)
        #expect(provider.requestCount == 2)
        // 第二次请求 wire = 裁剪前全量 [u, a1, t1]（t1 存在说明裁剪发生在最终收敛后）
        let histories = provider.capturedHistories
        guard histories.count >= 2 else {
            Issue.record("应捕获两次请求历史"); return
        }
        let second = histories[1]
        #expect(second.count == 3)
        #expect(second[2].role == .tool)
    }

    @Test("工具进度 chunk：onChunk 上报经 ChunkIndexer 转发 turn")
    func toolProgressChunksForwarded() async {
        let tool = ChunkyTool()
        let registry = ToolRegistry()
        await registry.register(tool)
        let provider = ScriptedProvider(script: [
            {
                LLMResponse(model: "m", content: [.text("")],
                            toolCalls: [LLM.ToolCallBlock(id: "c1", name: "chunky", arguments: "{}")],
                            finishReason: .stop)
            },
            {
                LLMResponse(model: "m", content: [.text("final")], finishReason: .stop)
            },
        ])
        let loop = AgentLoop(sessionID: SessionID(), llm: provider, tools: registry, model: "m")
        await loop.followup(UserMessage(content: [.text("q")]))
        let requested = await waitFor { provider.requestCount >= 2 }
        #expect(requested, "应发起两次 LLM 请求")
        let settled = await waitFor { await loop.currentStatus == .idle }
        #expect(settled)
        #expect(tool.emittedCount == 1, "工具应执行一次并上报进度")
        let result = await loop.lastTurnResult
        #expect(result.toolTraces.first?.ok == true)
        #expect(result.toolTraces.first?.output == "chunky done")
    }
}
