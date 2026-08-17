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
    let id: AgentID
    let sessionID: SessionID
    private var status: AgentStatus = .idle
    private var inbox: Inbox

    private let llm: any LLMProvider
    private let tools: ToolRegistry
    private let model: String
    private let systemPrompt: String?
    private let maxSteps: Int

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
        maxSteps: Int = 8
    ) {
        self.id = id
        self.sessionID = sessionID
        self.llm = llm
        self.tools = tools
        self.model = model
        self.systemPrompt = systemPrompt
        self.maxSteps = maxSteps
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
            Task { [weak self] in await self?.processInbox() }
        }
    }

    public func followup(_ message: UserMessage) {
        inbox.append(message, target: .nextTurn)
        Task { [weak self] in await self?.processInbox() }
    }

    public func inject(_ message: UserMessage) {
        inbox.append(message, target: .nextStep)
    }

    public func cancel(keepInbox: Bool) {
        if !keepInbox {
            inbox.clear()
        }
        status = .idle
    }

    public func whenIdle() async -> AgentResult {
        AgentResult(status: status)
    }

    /// 处理输入箱中的所有待处理批次
    public func processInbox() async {
        guard status == .idle else { return }
        status = .running
        defer { status = .idle }

        while let batch = inbox.claimNext() {
            lastResult = await runTurn(batch)
        }
    }

    // MARK: - Turn 执行

    private func runTurn(_ batch: [UserMessage]) async -> AgentResult {
        turnNumber += 1
        let turn = Turn(sessionID: sessionID, messages: batch, number: turnNumber)
        for userMessage in batch {
            history.append(Self.llmMessage(from: userMessage))
        }
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
                    return AgentResult(status: .idle, messages: [assistant])
                }

                // 执行全部工具调用并把结果回填上下文
                for call in calls {
                    let result = await executeToolCall(call)
                    await turn.recordToolResult(result)
                    history.append(Self.toolResultMessage(callID: call.id, result: result))
                }
            }
            // 达到步数上限
            let error = AgentError.stepLimitExceeded(maxSteps)
            await turn.fail(with: error)
            return AgentResult(status: .idle, error: error.localizedDescription)
        } catch {
            await turn.fail(with: error)
            return AgentResult(status: .idle, error: error.localizedDescription)
        }
    }

    private func executeToolCall(_ call: LLM.ToolCallBlock) async -> ToolResult {
        guard let tool = await tools.tool(named: call.name) else {
            let notFound = ToolResult(
                content: [.text("工具不存在：\(call.name)")],
                error: ToolError(name: call.name, code: "unknown_tool", message: "工具不存在：\(call.name)")
            )
            allToolResults.append(notFound)
            return notFound
        }
        let context = ToolRunContext(signal: CancellationToken(), sessionID: sessionID, metadata: [String: String]())
        do {
            let result = try await tool.execute(Self.parseArguments(call.arguments), context: context)
            allToolResults.append(result)
            return result
        } catch {
            let failed = ToolResult(
                content: [.text("工具执行失败：\(error.localizedDescription)")],
                error: ToolError(name: call.name, code: "exec_failed", message: error.localizedDescription)
            )
            allToolResults.append(failed)
            return failed
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
