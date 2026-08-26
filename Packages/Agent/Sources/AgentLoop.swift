import Foundation
import LLM
import ServiceContainer
import Session
import Tools

/// Agent 执行过程中的错误
public enum AgentError: Error, LocalizedError, Sendable {
    case stepLimitExceeded(Int)
    case unknownTool(String)

    public var errorDescription: String? {
        switch self {
        case let .stepLimitExceeded(n):
            "单轮工具调用步数超过上限（\(n)）"
        case let .unknownTool(name):
            "未知工具：\(name)"
        }
    }
}

/// 判定取消语义错误（Task 协作取消 / URLSession 任务取消），与真实 LLM 错误区分
private func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let urlError = error as? URLError, urlError.code == .cancelled {
        return true
    }
    return false
}

/// 取消时 turn 中性收敛：无错误消息（不污染会话流）、无最终回答、无历史污染
private func cancelledResult(_ turn: Turn, _ steps: [AssistantMessage],
                             _ traces: [ToolTraceEntry]) async -> AgentResult {
    await turn.complete()
    return AgentResult(status: .idle, steps: steps, toolTraces: traces)
}

/// Agent Loop — 驱动 Agent 对话循环
///
/// 每个 turn：把用户消息追加进上下文 → 循环调用 LLM →
/// 若返回工具调用则经 ToolRegistry 真实执行并把结果回填上下文 →
/// 直到模型给出最终回答或达到步数上限。
/// Agent 实时进度事件（主聊天展示工具执行状态；nil 回调 = 无订阅）
public enum AgentProgress: Sendable, Equatable {
    case toolStarted(name: String)
    case toolFinished(name: String, ok: Bool)
    case finalAnswer
}

public actor AgentLoop {
    public let id: AgentID
    public let sessionID: SessionID
    public nonisolated(unsafe) var status: AgentStatus = .idle
    private var inbox: Inbox

    /// whenIdle() 等待队列（由 processInbox 完成 / cancel / 任务取消 唤醒；OnceBox 保证只 resume 一次）
    private var idleWaiters: [OnceIdleContinuation] = []
    /// 取消标记：置位后 whenIdle 立即返回；新的 send/followup 会清除
    private var cancelFlag = false
    /// 在途 turn Task（processInbox 创建、收敛后置 nil；cancel() 联动取消以中断在途 LLM 调用）
    private var inFlightTurn: Task<AgentResult, Never>?

    private let llm: any LLMProvider
    private let tools: ToolRegistry
    /// 当前模型（会话级持久循环可跨轮更新；历史为厂商中立 wire 消息，安全热切）
    private var model: String
    /// 系统提示词（每轮可刷新：记忆注入 / 用户配置变化）
    private var systemPrompt: String?
    /// 生成上限 token（请求参数，nil = 不下发；跨轮可更新）
    private var maxTokens: Int?
    /// 思考等级（请求参数，nil/.off = 不下发 reasoning_effort；跨轮可更新）
    private var thinkingLevel: LLM.ThinkingLevel?
    private let maxSteps: Int
    /// 上下文保留上限：每轮 turn 结束后裁剪到最近 N 条（防长会话内存无界增长）
    private let maxHistoryMessages: Int
    /// 工具执行器（参数校验/超时熔断/输出二次校验统一链路）
    private let executor: ToolExecutor
    /// 会话工作目录解析器（nil = 不下发，工具沿用进程 cwd）
    private let workingDirectoryProvider: (@Sendable (SessionID) async -> URL?)?
    /// 实时进度回调（跨 actor 调用，仅用于 UI 展示；生产/测试默认 nil）
    public nonisolated(unsafe) var onProgress: (@Sendable (AgentProgress) -> Void)?

    /// 对话上下文（LLM 侧消息）
    private var history: [LLM.Message] = []
    /// 已开始的 turn 数（观察/测试用；完成时 lastResult 已写入）
    public private(set) var turnNumber: Int = 0

    /// 最近一次 turn 的结果
    public private(set) var lastResult: AgentResult = .init(status: .idle)

    /// 历史中执行过的全部工具结果（调试/测试用）
    public private(set) var allToolResults: [ToolResult] = []

    public init(
        id: AgentID = AgentID(),
        sessionID: SessionID,
        llm: any LLMProvider,
        tools: ToolRegistry,
        model: String,
        systemPrompt: String? = nil,
        maxSteps: Int = 8,
        maxHistoryMessages: Int = 200,
        maxTokens: Int? = nil,
        thinkingLevel: LLM.ThinkingLevel? = nil,
        executor: ToolExecutor? = nil,
        // 种子历史（如从会话存储恢复的既有上下文）；入参后立即按上限裁剪
        history: [LLM.Message] = [],
        // 会话工作目录解析（P0.1.5：会话工作区 agents/\<sessionID\> 下发到工具上下文）
        workingDirectoryProvider: (@Sendable (SessionID) async -> URL?)? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.llm = llm
        self.tools = tools
        self.model = model
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.thinkingLevel = thinkingLevel
        self.maxSteps = maxSteps
        self.maxHistoryMessages = max(4, maxHistoryMessages)
        self.executor = executor ?? ToolExecutor()
        self.history = Self.trimHistory(history, max: maxHistoryMessages)
        self.workingDirectoryProvider = workingDirectoryProvider
        inbox = Inbox()
    }

    public var currentStatus: AgentStatus {
        status
    }

    /// 跨轮更新本轮上下文（模型 / 系统提示词）；历史完整保留。
    /// 会话级持久循环专用：切换模型或提示词配置后调用，工具上下文不丢失。
    public func setTurnContext(model: String, systemPrompt: String?, maxTokens: Int?, thinkingLevel: LLM.ThinkingLevel?) {
        (self.model, self.systemPrompt, self.maxTokens, self.thinkingLevel) = (model, systemPrompt, maxTokens, thinkingLevel)
    }

    public var lastTurnResult: AgentResult {
        lastResult
    }

    public func send(_ message: UserMessage, target: InboxTarget, wakeup: Bool) {
        inbox.append(message, target: target)
        if wakeup {
            cancelFlag = false
            Task { [weak self] in await self?.processInbox() }
        }
    }

    public func followup(_ message: UserMessage) {
        inbox.append(message, target: .nextTurn)
        cancelFlag = false
        Task { [weak self] in await self?.processInbox() }
    }

    public func inject(_ message: UserMessage) {
        inbox.append(message, target: .nextStep)
    }

    public func cancel(keepInbox: Bool) {
        if !keepInbox {
            inbox.clear()
        }
        cancelFlag = true
        // 在途 turn 联动取消（P2 ①）：支持取消的 provider（全部 URLSession 适配器）立即中止请求；
        // 不支持取消的 provider 在其自身请求时长内完成后，runTurn 丢弃延迟响应（不进 wire 历史）
        inFlightTurn?.cancel()
        if status != .idle {
            // 先唤醒 whenIdle 等待者（调用方任务通常已取消，结果仅作收敛）；
            // 不在此翻 status：旧 turn Task 尚未收敛，status 由 processInbox defer 释放，
            // 防止旧 turn 未收敛时新 turn 准入（并发写 history 竞态）
            notifyIdleWaiters()
        }
    }

    /// 等待 Agent 回到空闲（inbox 无待处理批次）
    ///
    /// - 空闲且无待处理：立即返回最近一次 turn 的结果
    /// - 运行中（或消息已入队但 processInbox 尚未启动）：挂起，
    ///   直到 processInbox 完成或 cancel() 唤醒
    public func whenIdle() async -> AgentResult {
        if cancelFlag {
            return AgentResult(status: .idle)
        }
        if status == .idle, !inbox.hasPending {
            return lastResult
        }
        // 取消感知（P2）：等待方任务被取消（如 WebUI 超时）时立即原子唤醒，
        // 不再悬挂到 turn 自然结束（原实现 Task 取消不 resume continuation，孤儿任务有界挂起）
        let box = OnceIdleContinuation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AgentResult, Never>) in
                box.set(continuation)
                self.idleWaiters.append(box)
            }
        } onCancel: { [weak self] in
            Task { [weak self] in
                await self?.wakeIdleWaiter(box)
            }
        }
    }

    /// 取消路径唤醒：立即以当前结果 resume（调用方任务已取消，结果仅作收敛）；
    /// 不中断运行中的 turn（OnceBox 与正常完成路径互斥，恰好一方生效）
    private func wakeIdleWaiter(_ box: OnceIdleContinuation) {
        idleWaiters.removeAll { $0 === box }
        box.resume(lastResult)
    }

    /// 处理输入箱中的所有待处理批次
    public func processInbox() async {
        guard status == .idle else { return }
        status = .running
        defer {
            status = .idle
            notifyIdleWaiters()
        }

        while !cancelFlag, let batch = inbox.claimNext() {
            // turn 在可取消 Task 中执行：cancel() 可中断在途 LLM 调用（联动取消，P2 ①）；
            // status 保持 .running 直至 Task 收敛，保证 turn 串行（无并发 history 写）
            let turnTask = Task { await self.runTurn(batch) }
            inFlightTurn = turnTask
            lastResult = await turnTask.value
            inFlightTurn = nil
        }
    }

    /// 唤醒全部 whenIdle() 等待者并清空队列（保证每个 continuation 只 resume 一次）
    private func notifyIdleWaiters() {
        guard !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters {
            waiter.resume(lastResult)
        }
    }

    /// continuation 单射盒：正常完成 / cancel / 任务取消 三条路径竞争时保证恰好 resume 一次
    private final class OnceIdleContinuation: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<AgentResult, Never>?

        func set(_ continuation: CheckedContinuation<AgentResult, Never>) {
            lock.withLock { self.continuation = continuation }
        }

        func resume(_ result: AgentResult) {
            guard let c = lock.withLock({ let v = continuation; continuation = nil; return v }) else { return }
            c.resume(returning: result)
        }
    }

    // MARK: - Turn 执行

    private func runTurn(_ batch: [UserMessage]) async -> AgentResult {
        turnNumber += 1
        let turn = Turn(sessionID: sessionID, messages: batch, number: turnNumber)
        for userMessage in batch {
            history.append(Self.llmMessage(from: userMessage))
        }
        var stepMessages: [AssistantMessage] = []
        var toolTraces: [ToolTraceEntry] = []
        do {
            var step = 0
            while step < maxSteps {
                // 已取消：中性结束本 turn，不再发起新 LLM 调用 / 执行新工具
                if Task.isCancelled {
                    return await cancelledResult(turn, stepMessages, toolTraces)
                }
                step += 1
                // 能力门控：画像不支持工具调用时不下发 tools（如未细分的本地引擎），模型直接作答
                let request = await LLMRequest(model: model, messages: history, systemPrompt: systemPrompt,
                                               tools: llm.profile.supportsToolCalls ? tools.schemas() : nil,
                                               maxTokens: maxTokens, thinkingLevel: thinkingLevel)
                let response = try await llm.request(request)
                // 已取消：不支持取消的 provider 延迟返回的响应必须丢弃（不进 wire 历史、不作最终回答）
                if Task.isCancelled {
                    return await cancelledResult(turn, stepMessages, toolTraces)
                }

                // 记录助手消息（含工具调用块，下一轮 wire 请求需回传）
                history.append(Self.assistantHistoryMessage(response))
                stepMessages.append(makeStepMessage(step: step, response: response))

                let calls = response.toolCalls ?? []
                guard !calls.isEmpty else {
                    // 最终回答
                    onProgress?(.finalAnswer)
                    await turn.complete()
                    let text = Self.text(from: response.content)
                    let assistant = AssistantMessage(
                        turn: turnNumber,
                        step: step,
                        content: [.text(text)],
                        provider: llm.id,
                        model: response.model,
                        usage: response.usage.map {
                            Session.TokenUsage(promptTokens: $0.promptTokens,
                                               completionTokens: $0.completionTokens,
                                               totalTokens: $0.totalTokens)
                        }
                    )
                    trimHistory()
                    return AgentResult(status: .idle, messages: [assistant], steps: stepMessages, toolTraces: toolTraces)
                }

                // 执行全部工具调用：回填上下文并收集轨迹（前后发射进度事件供 UI 实时展示）
                await executeToolBatch(calls, turn: turn, traces: &toolTraces)
            }
            // 达到步数上限
            let error = AgentError.stepLimitExceeded(maxSteps)
            await turn.fail(with: error)
            trimHistory()
            return AgentResult(status: .idle, error: error.localizedDescription, steps: stepMessages, toolTraces: toolTraces)
        } catch {
            // 在途 LLM 调用被 cancel 中断（CancellationError / URLError.cancelled）：中性收敛
            if isCancellationError(error) {
                return await cancelledResult(turn, stepMessages, toolTraces)
            }
            await turn.fail(with: error)
            return AgentResult(status: .idle, error: error.localizedDescription, steps: stepMessages, toolTraces: toolTraces)
        }
    }

    /// 执行一批工具调用：逐条发射进度事件、回填历史、收集 UI 轨迹
    private func executeToolBatch(_ calls: [LLM.ToolCallBlock], turn: Turn,
                                  traces: inout [ToolTraceEntry]) async {
        for call in calls {
            onProgress?(.toolStarted(name: call.name))
            let result = await executeToolCall(call, turn: turn)
            onProgress?(.toolFinished(name: call.name, ok: result.error == nil))
            await turn.recordToolResult(result)
            history.append(Self.toolResultMessage(callID: call.id, result: result))
            traces.append(ToolTraceEntry(
                id: traces.count,
                name: call.name,
                arguments: call.arguments,
                output: Self.traceOutput(from: result),
                ok: result.error == nil
            ))
        }
    }

    /// 助手消息入历史：content + toolCall 块（按 id 去重防双源；
    /// 下一轮 wire 请求需回传 assistant tool_calls 才能让模型看到工具调用上下文）
    private static func assistantHistoryMessage(_ response: LLMResponse) -> LLM.Message {
        var blocks = response.content
        if let calls = response.toolCalls {
            let existing = Set(response.content.compactMap { block -> String? in
                if case let .toolCall(tc) = block {
                    return tc.id
                }
                return nil
            })
            blocks.append(contentsOf: calls.filter { !existing.contains($0.id) }.map { .toolCall($0) })
        }
        return LLM.Message(role: .assistant, content: blocks, source: .model)
    }

    /// 裁剪上下文到最近 max 条（保留工具调用/结果的配对完整性：
    /// 不留下“无主”的 tool 结果消息在队首）
    /// internal（非 private）：测试缝，直测队首孤立 tool 结果丢弃分支（L365 循环体）
    static func trimHistory(_ history: [LLM.Message], max: Int) -> [LLM.Message] {
        guard history.count > max else { return history }
        var keep = history.suffix(max)
        // 队首若为 tool 结果（其 assistant 调用已被裁掉），继续丢弃直到安全边界
        while let first = keep.first, first.role == .tool {
            keep = keep.dropFirst()
        }
        return Array(keep)
    }

    private func trimHistory() {
        history = Self.trimHistory(history, max: maxHistoryMessages)
    }

    /// 工具输出 → UI 摘要文本（截断 2000 字符；错误优先展示）
    static func traceOutput(from result: ToolResult) -> String {
        let text = result.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined(separator: "\n")
        if let error = result.error {
            let head = "错误（\(error.code)）：\(error.message)"
            return text.isEmpty ? head : head + "\n" + String(text.prefix(800))
        }
        return String(text.prefix(2000))
    }

    /// 构造当前步的助手消息（content + 工具调用块按 id 去重合并，供执行过程展示/观测）
    private func makeStepMessage(step: Int, response: LLMResponse) -> AssistantMessage {
        var blocks = response.content.map(Self.sessionBlock(from:))
        if let calls = response.toolCalls {
            let existing = Set(response.content.compactMap { block -> String? in
                if case let .toolCall(tc) = block {
                    return tc.id
                }
                return nil
            })
            blocks.append(contentsOf: calls.filter { !existing.contains($0.id) }.map {
                Self.sessionBlock(from: .toolCall($0))
            })
        }
        return AssistantMessage(
            turn: turnNumber,
            step: step,
            content: blocks,
            provider: llm.id,
            model: response.model,
            usage: response.usage.map {
                Session.TokenUsage(promptTokens: $0.promptTokens,
                                   completionTokens: $0.completionTokens,
                                   totalTokens: $0.totalTokens)
            }
        )
    }

    private func executeToolCall(_ call: LLM.ToolCallBlock, turn: Turn) async -> ToolResult {
        // 统一执行链路：查找 → 参数校验 → 熔断 → 超时 → 执行 → 输出二次校验
        let indexer = ChunkIndexer()
        let workingDirectory = await workingDirectoryProvider?(sessionID)
        let context = ToolRunContext(
            signal: CancellationToken(),
            sessionID: sessionID,
            metadata: [String: String](),
            onChunk: { [turn] chunk in
                Task {
                    await turn.receiveChunk(LLM.StreamChunk(
                        type: "tool_progress",
                        data: Data(chunk.utf8),
                        index: indexer.next()
                    ))
                }
            },
            workingDirectory: workingDirectory
        )
        let toolCall = ToolCall(id: call.id, name: call.name, arguments: Self.parseArguments(call.arguments))
        let result = await executor.execute(toolCall, in: tools, context: context)
        allToolResults.append(result)
        return result
    }

    /// 工具流式进度块序号（跨 chunk 递增；ToolRunContext.onChunk 为同步回调，用锁保证原子）
    private final class ChunkIndexer: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.withLock {
                defer { value += 1 }
                return value
            }
        }
    }

    // MARK: - 类型转换与解析

    /// SessionRecord.UserMessage → LLM.Message
    static func llmMessage(from message: UserMessage) -> LLM.Message {
        LLM.Message(role: .user, content: message.content.map(convertBlock), source: .user)
    }

    /// 工具结果 → 回填上下文的 LLM.Message（role: .tool）
    static func toolResultMessage(callID: String, result: ToolResult) -> LLM.Message {
        LLM.Message(
            role: .tool,
            content: [
                .toolResult(LLM.ToolResultBlock(toolCallId: callID, content: result.content, isError: result.error != nil)),
            ],
            source: .tool
        )
    }

    /// Session.ContentBlock → LLM.ContentBlock（两侧结构同构，逐 case 映射）
    static func convertBlock(_ block: Session.ContentBlock) -> LLM.ContentBlock {
        switch block {
        case let .text(s):
            .text(s)
        case let .reasoning(s):
            .reasoning(s)
        case let .image(img):
            .image(LLM.ImageBlock(mimeType: img.mimeType, data: img.data, width: img.width, height: img.height))
        case let .toolCall(tc):
            .toolCall(LLM.ToolCallBlock(id: tc.id, name: tc.name, arguments: tc.arguments))
        case let .toolResult(tr):
            .toolResult(LLM.ToolResultBlock(toolCallId: tr.toolCallId, content: tr.content.map(convertBlock), isError: tr.isError))
        }
    }

    /// LLM.ContentBlock → Session.ContentBlock（convertBlock 的反向映射；步骤消息记录用）
    static func sessionBlock(from block: LLM.ContentBlock) -> Session.ContentBlock {
        switch block {
        case let .text(s):
            .text(s)
        case let .reasoning(s):
            .reasoning(s)
        case let .image(img):
            .image(Session.ImageBlock(mimeType: img.mimeType, data: img.data, width: img.width, height: img.height))
        case let .toolCall(tc):
            .toolCall(Session.ToolCallBlock(id: tc.id, name: tc.name, arguments: tc.arguments))
        case let .toolResult(tr):
            .toolResult(Session.ToolResultBlock(toolCallId: tr.toolCallId,
                                                content: tr.content.map { sessionBlock(from: $0) },
                                                isError: tr.isError))
        }
    }

    /// 提取回答中的文本内容
    static func text(from blocks: [LLM.ContentBlock]) -> String {
        blocks.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
    }

    /// 解析工具调用参数（JSON 对象 → [String: String]，非字符串值序列化为 JSON 文本）
    static func parseArguments(_ json: String) -> [String: String] {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in dict {
            switch value {
            case let s as String:
                result[key] = s
            case let n as NSNumber:
                if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                    result[key] = n.boolValue ? "true" : "false"
                } else {
                    result[key] = n.stringValue
                }
            case let container as [Any]:
                if let d = try? JSONSerialization.data(withJSONObject: container),
                   let s = String(data: d, encoding: .utf8) {
                    result[key] = s
                }
            case let container as [String: Any]:
                if let d = try? JSONSerialization.data(withJSONObject: container),
                   let s = String(data: d, encoding: .utf8) {
                    result[key] = s
                }
            default:
                result[key] = String(describing: value)
            }
        }
        return result
    }
}

// MARK: - Agent 协议一致性（供 SubagentCoordinator 等编排使用）

extension AgentLoop: Agent {}
