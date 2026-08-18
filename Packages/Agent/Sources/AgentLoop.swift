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

/// Agent Loop — 驱动 Agent 对话循环
///
/// 每个 turn：把用户消息追加进上下文 → 循环调用 LLM →
/// 若返回工具调用则经 ToolRegistry 真实执行并把结果回填上下文 →
/// 直到模型给出最终回答或达到步数上限。
public actor AgentLoop {
    public let id: AgentID
    public let sessionID: SessionID
    public nonisolated(unsafe) var status: AgentStatus = .idle
    private var inbox: Inbox

    /// whenIdle() 等待队列（由 processInbox 完成 / cancel 唤醒）
    private var idleWaiters: [CheckedContinuation<AgentResult, Never>] = []
    /// 取消标记：置位后 whenIdle 立即返回；新的 send/followup 会清除
    private var cancelFlag = false

    private let llm: any LLMProvider
    private let tools: ToolRegistry
    private let model: String
    private let systemPrompt: String?
    private let maxSteps: Int
    /// 上下文保留上限：每轮 turn 结束后裁剪到最近 N 条（防长会话内存无界增长）
    private let maxHistoryMessages: Int
    /// 工具执行器（参数校验/超时熔断/输出二次校验统一链路）
    private let executor: ToolExecutor

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
        executor: ToolExecutor? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.llm = llm
        self.tools = tools
        self.model = model
        self.systemPrompt = systemPrompt
        self.maxSteps = maxSteps
        self.maxHistoryMessages = max(4, maxHistoryMessages)
        self.executor = executor ?? ToolExecutor()
        inbox = Inbox()
    }

    public var currentStatus: AgentStatus {
        status
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
        // 打断运行中的 turn：标记 idle 并唤醒 whenIdle 等待者
        // （在途 LLM 调用在后台自行完成，不再阻塞协调器）
        if status != .idle {
            status = .idle
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
        return await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    /// 处理输入箱中的所有待处理批次
    public func processInbox() async {
        guard status == .idle else { return }
        status = .running
        defer {
            status = .idle
            notifyIdleWaiters()
        }

        while let batch = inbox.claimNext() {
            lastResult = await runTurn(batch)
        }
    }

    /// 唤醒全部 whenIdle() 等待者并清空队列（保证每个 continuation 只 resume 一次）
    private func notifyIdleWaiters() {
        guard !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters {
            waiter.resume(returning: lastResult)
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
        do {
            var step = 0
            while step < maxSteps {
                step += 1
                let request = await LLMRequest(
                    model: model,
                    messages: history,
                    systemPrompt: systemPrompt,
                    tools: tools.schemas()
                )
                let response = try await llm.request(request)

                // 记录助手消息（含可能的工具调用块）
                history.append(LLM.Message(role: .assistant, content: response.content, source: .model))
                stepMessages.append(makeStepMessage(step: step, response: response))

                let calls = response.toolCalls ?? []
                guard !calls.isEmpty else {
                    // 最终回答
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
                    return AgentResult(status: .idle, messages: [assistant], steps: stepMessages)
                }

                // 执行全部工具调用并把结果回填上下文
                for call in calls {
                    let result = await executeToolCall(call, turn: turn)
                    await turn.recordToolResult(result)
                    history.append(Self.toolResultMessage(callID: call.id, result: result))
                }
            }
            // 达到步数上限
            let error = AgentError.stepLimitExceeded(maxSteps)
            await turn.fail(with: error)
            trimHistory()
            return AgentResult(status: .idle, error: error.localizedDescription, steps: stepMessages)
        } catch {
            await turn.fail(with: error)
            return AgentResult(status: .idle, error: error.localizedDescription, steps: stepMessages)
        }
    }

    /// 裁剪上下文到最近 maxHistoryMessages 条（保留工具调用/结果的配对完整性：
    /// 不留下“无主”的 tool 结果消息在队首）
    private func trimHistory() {
        guard history.count > maxHistoryMessages else { return }
        var keep = history.suffix(maxHistoryMessages)
        // 队首若为 tool 结果（其 assistant 调用已被裁掉），继续丢弃直到安全边界
        while let first = keep.first, first.role == .tool {
            keep = keep.dropFirst()
        }
        history = Array(keep)
    }

    /// 构造当前步的助手消息（含工具调用块，供执行过程展示）
    private func makeStepMessage(step: Int, response: LLMResponse) -> AssistantMessage {
        AssistantMessage(
            turn: turnNumber,
            step: step,
            content: response.content.map(Self.sessionBlock(from:)),
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
            }
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
