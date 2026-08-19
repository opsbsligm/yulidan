import Foundation

/// OpenAI 兼容 HTTP 客户端 — 同时服务于 OpenAI / DeepSeek / 本地 OpenAI 兼容服务 (Ollama、vLLM、LM Studio)
/// 实现非流式 request（含 tools 下发 / tool_calls / reasoning_content / finish_reason 解析）与 SSE 流式 stream。
public struct OpenAICompatChat: Sendable {
    public let apiKey: String
    public let baseURL: URL
    public var timeout: TimeInterval = 120
    public let session: URLSession

    public init(apiKey: String, baseURL: URL, timeout: TimeInterval = 120, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    // MARK: - 请求体构造

    /// 消息可序列化部分（文本 / 工具调用 / 工具结果）
    private struct WireMessageParts {
        let text: String
        let toolCalls: [ChatToolCallOutDTO]
        let toolResults: [(id: String, text: String)]
    }

    private static func classify(_ m: Message) -> WireMessageParts {
        var textParts: [String] = []
        var toolCalls: [ChatToolCallOutDTO] = []
        var toolResults: [(id: String, text: String)] = []
        for block in m.content {
            switch block {
            case let .text(t):
                if !t.isEmpty {
                    textParts.append(t)
                }
            case let .toolCall(tc):
                toolCalls.append(ChatToolCallOutDTO(id: tc.id, type: "function",
                                                    function: .init(name: tc.name, arguments: tc.arguments)))
            case let .toolResult(tr):
                let contentText = tr.content.compactMap { block -> String? in
                    if case let .text(t) = block {
                        return t
                    }
                    return nil
                }.joined(separator: "\n")
                toolResults.append((tr.toolCallId, contentText))
            case .reasoning, .image:
                break
            }
        }
        return WireMessageParts(text: textParts.joined(separator: "\n"),
                                toolCalls: toolCalls,
                                toolResults: toolResults)
    }

    /// 序列化对话历史（含工具调用 / 工具结果）为 wire 消息序列。
    /// - assistant + toolCall → `{role:"assistant", content, tool_calls:[...]}`（content 可为 null）
    /// - tool 结果消息       → `{role:"tool", tool_call_id, content}`
    /// - reasoning / image 块不回传（各厂商协议均不接受）
    private static func wireMessages(for m: Message, parts: WireMessageParts) -> [ChatMessageDTO] {
        switch m.role {
        case .assistant:
            if parts.toolCalls.isEmpty {
                return parts.text.isEmpty ? [] : [.init(role: "assistant", content: parts.text)]
            }
            return [.init(role: "assistant",
                          content: parts.text.isEmpty ? nil : parts.text,
                          toolCalls: parts.toolCalls)]
        case .tool, .user:
            if parts.toolResults.isEmpty {
                return parts.text.isEmpty ? [] : [.init(role: m.role.rawValue, content: parts.text)]
            }
            return parts.toolResults.map { .init(role: "tool", content: $0.text, toolCallId: $0.id) }
        case .system:
            return parts.text.isEmpty ? [] : [.init(role: "system", content: parts.text)]
        }
    }

    private static func flatMessages(_ messages: [Message], systemPrompt: String?) -> [ChatMessageDTO] {
        var out: [ChatMessageDTO] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            out.append(.init(role: "system", content: systemPrompt))
        }
        for m in messages {
            out += Self.wireMessages(for: m, parts: Self.classify(m))
        }
        return out
    }

    /// 构造 chat/completions 请求（stream=true 时注入 "stream": true 并声明 SSE Accept）
    private func makeRequest(model: String,
                             messages: [Message],
                             systemPrompt: String? = nil,
                             tools: [ToolSchema]? = nil,
                             maxTokens: Int? = nil,
                             temperature: Double? = nil,
                             extraHeaders: [String: String] = [:],
                             stream: Bool) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if stream {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        var dto = ChatRequestDTO(model: model,
                                 messages: Self.flatMessages(messages, systemPrompt: systemPrompt),
                                 maxTokens: maxTokens,
                                 temperature: temperature)
        if let tools, !tools.isEmpty {
            dto.tools = tools.map(ChatToolDTO.init)
        }
        var payload = try JSONEncoder().encode(dto)
        if stream {
            if var obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                obj["stream"] = true
                payload = try JSONSerialization.data(withJSONObject: obj)
            }
        }
        req.httpBody = payload
        return req
    }

    // MARK: - 非流式

    /// 发起一次完整的 chat completion 请求，返回结构化结果（文本 / reasoning / 工具调用 / finishReason / usage）
    public func complete(model: String,
                         messages: [Message],
                         systemPrompt: String? = nil,
                         tools: [ToolSchema]? = nil,
                         maxTokens: Int? = nil,
                         temperature: Double? = nil,
                         extraHeaders: [String: String] = [:]) async throws -> CompletionResult {
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        let req = try makeRequest(model: model, messages: messages, systemPrompt: systemPrompt,
                                  tools: tools, maxTokens: maxTokens, temperature: temperature,
                                  extraHeaders: extraHeaders, stream: false)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("无法解析 HTTP 响应")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "(无响应体)"
            throw LLMError.httpError(status: http.statusCode, body: String(msg.prefix(500)))
        }
        return try Self.parseCompletionResponse(data)
    }

    /// 解析 chat/completions 响应为结构化结果
    static func parseCompletionResponse(_ data: Data) throws -> CompletionResult {
        let r: ChatCompletionRespDTO
        do {
            r = try JSONDecoder().decode(ChatCompletionRespDTO.self, from: data)
        } catch let e as LLMError {
            throw e
        } catch {
            throw LLMError.decodingError("响应解析失败: \(error.localizedDescription)")
        }
        guard let first = r.choices.first else {
            throw LLMError.emptyResponse
        }
        let message = first.message
        let toolCalls = (message.toolCalls ?? []).enumerated().map { i, dto in
            ToolCallBlock(id: dto.id ?? "call-\(i)",
                          name: dto.function?.name ?? "unknown",
                          arguments: dto.function?.arguments ?? "{}")
        }
        let reasoning = message.reasoningContent.flatMap { $0.isEmpty ? nil : $0 }
        let usage = r.usage.map {
            TokenUsage(promptTokens: $0.promptTokens ?? 0,
                       completionTokens: $0.completionTokens ?? 0,
                       totalTokens: $0.totalTokens ?? 0)
        }
        return CompletionResult(content: message.content ?? "",
                                reasoning: reasoning,
                                toolCalls: toolCalls,
                                finishReason: Self.mapFinishReason(first.finishReason),
                                usage: usage)
    }

    /// finish_reason wire 值 → 统一 FinishReason（nil / 未知值按 .stop 兜底）
    public static func mapFinishReason(_ raw: String?) -> LLMResponse.FinishReason {
        switch raw {
        case "tool_calls"?, "function_call"?:
            .toolCalls
        case "length"?:
            .length
        case "stop"?, nil:
            .stop
        default:
            .stop
        }
    }

    // MARK: - SSE 解析

    /// 解析单行 SSE 文本为增量内容；非 data: 行 / [DONE] / 解析失败返回 nil
    public static func sseDeltaText(from line: String) -> String? {
        sseDelta(from: line)?.content
    }

    /// 解析单行 SSE 文本为结构化增量载荷（文本 / reasoning / tool_calls 片段 / finish_reason / usage）
    public static func sseDelta(from line: String) -> OpenAISSEPayload? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let d = try? JSONDecoder().decode(ChatDeltaDTO.self, from: data)
        else { return nil }
        return OpenAISSEPayload(choice: d.choices?.first, usage: d.usage)
    }

    // MARK: - SSE 流式

    /// 流式聚合状态（tool_calls 片段 / 最近 finish / 最近 usage）
    private struct SSEAggregationState: Sendable {
        var accumulator = ToolCallDeltaAccumulator()
        var finishReason: LLMResponse.FinishReason?
        var usage: TokenUsage?
    }

    /// 处理单条 SSE data 行：更新聚合状态，返回文本增量事件（无则 nil）
    private func sseLineEvent(_ line: String, state: inout SSEAggregationState) -> OpenAIStreamEvent? {
        guard let payload = Self.sseDelta(from: line) else { return nil }
        if let finish = payload.finishReason {
            state.finishReason = Self.mapFinishReason(finish)
        }
        if let usage = payload.usage {
            state.usage = usage
        }
        for delta in payload.toolCallDeltas {
            state.accumulator.apply(delta)
        }
        guard let content = payload.content else { return nil }
        return .text(content)
    }

    /// 流式 chat completion — 结构化事件流：文本增量 + 终态事件（聚合 tool_calls / finishReason / usage）
    public func streamEvents(model: String,
                             messages: [Message],
                             systemPrompt: String? = nil,
                             tools: [ToolSchema]? = nil,
                             maxTokens: Int? = nil,
                             temperature: Double? = nil,
                             extraHeaders: [String: String] = [:]) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try makeRequest(model: model, messages: messages, systemPrompt: systemPrompt,
                                              tools: tools, maxTokens: maxTokens, temperature: temperature,
                                              extraHeaders: extraHeaders, stream: true)
                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.networkError("无法解析 HTTP 响应")
                    }
                    guard (200 ..< 300).contains(http.statusCode) else {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line
                        }
                        throw LLMError.httpError(status: http.statusCode, body: String(errBody.prefix(500)))
                    }
                    var state = SSEAggregationState()
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        if let event = sseLineEvent(line, state: &state) {
                            continuation.yield(event)
                        }
                    }
                    continuation.yield(.done(finishReason: state.finishReason ?? .stop,
                                             usage: state.usage,
                                             toolCalls: state.accumulator.toolCalls))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 流式 chat completion，逐块 yield 增量文本（兼容旧调用方；富事件请用 streamEvents）
    public func stream(model: String,
                       messages: [Message],
                       systemPrompt: String? = nil,
                       tools: [ToolSchema]? = nil,
                       maxTokens: Int? = nil,
                       temperature: Double? = nil,
                       extraHeaders: [String: String] = [:]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in streamEvents(model: model, messages: messages,
                                                        systemPrompt: systemPrompt, tools: tools,
                                                        maxTokens: maxTokens, temperature: temperature,
                                                        extraHeaders: extraHeaders) {
                        if case let .text(t) = event {
                            continuation.yield(t)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 连接测试

    /// 轻量连接测试：GET /models（OpenAI 兼容端点）
    public func checkConnection() async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let url = baseURL.appendingPathComponent("models")
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.networkError("无法解析响应") }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(status: http.statusCode, body: String(msg.prefix(300)))
        }
        return "连接成功"
    }
}

// MARK: - 结构化结果 / 流事件 / SSE 载荷

/// 非流式 completion 结构化结果 — (content, usage) 的超集，携带 reasoning / tool_calls / finishReason
public struct CompletionResult: Sendable {
    public let content: String
    public let reasoning: String?
    public let toolCalls: [ToolCallBlock]
    public let finishReason: LLMResponse.FinishReason
    public let usage: TokenUsage?

    public init(content: String,
                reasoning: String? = nil,
                toolCalls: [ToolCallBlock] = [],
                finishReason: LLMResponse.FinishReason = .stop,
                usage: TokenUsage? = nil) {
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }
}

/// OpenAI 兼容流式事件
public enum OpenAIStreamEvent: Sendable {
    case text(String)
    case done(finishReason: LLMResponse.FinishReason, usage: TokenUsage?, toolCalls: [ToolCallBlock])
}

/// SSE tool_calls 片段（按 index 归并）
public struct OpenAISSEToolCallDelta: Sendable, Equatable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let argumentsFragment: String?

    public init(index: Int, id: String?, name: String?, argumentsFragment: String?) {
        self.index = index
        self.id = id
        self.name = name
        self.argumentsFragment = argumentsFragment
    }
}

/// SSE 单行 data: 的结构化载荷
public struct OpenAISSEPayload: Sendable {
    public let content: String?
    public let reasoningContent: String?
    public let toolCallDeltas: [OpenAISSEToolCallDelta]
    public let finishReason: String?
    public let usage: TokenUsage?

    public init(content: String? = nil,
                reasoningContent: String? = nil,
                toolCallDeltas: [OpenAISSEToolCallDelta] = [],
                finishReason: String? = nil,
                usage: TokenUsage? = nil) {
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCallDeltas = toolCallDeltas
        self.finishReason = finishReason
        self.usage = usage
    }

    /// 由 wire delta DTO 构造（sseDelta 内部使用）
    init(choice: ChatDeltaChoiceDTO?, usage: ChatUsageDTO?) {
        let message = choice?.effectiveMessage
        content = message?.content.flatMap { $0.isEmpty ? nil : $0 }
        reasoningContent = message?.reasoningContent.flatMap { $0.isEmpty ? nil : $0 }
        toolCallDeltas = (message?.toolCalls ?? []).map { tc in
            OpenAISSEToolCallDelta(index: tc.index ?? 0,
                                   id: tc.id,
                                   name: tc.function?.name,
                                   argumentsFragment: tc.function?.arguments)
        }
        finishReason = choice?.finishReason
        self.usage = usage.map {
            TokenUsage(promptTokens: $0.promptTokens ?? 0,
                       completionTokens: $0.completionTokens ?? 0,
                       totalTokens: $0.totalTokens ?? 0)
        }
    }
}

/// SSE tool_calls 片段聚合器 — 多个 delta 按 index 归并（id/name 仅在首个片段出现，arguments 逐片拼接）
public struct ToolCallDeltaAccumulator: Sendable {
    private struct Entry {
        var id: String?
        var name: String?
        var arguments: String
    }

    private var entries: [Int: Entry] = [:]
    private var order: [Int] = []

    public init() {}

    public mutating func apply(_ delta: OpenAISSEToolCallDelta) {
        if entries[delta.index] == nil {
            order.append(delta.index)
        }
        var entry = entries[delta.index] ?? Entry(id: nil, name: nil, arguments: "")
        if let id = delta.id {
            entry.id = id
        }
        if let name = delta.name {
            entry.name = name
        }
        if let fragment = delta.argumentsFragment {
            entry.arguments += fragment
        }
        entries[delta.index] = entry
    }

    /// 归并后的工具调用（顺序 = index 首次出现顺序）
    public var toolCalls: [ToolCallBlock] {
        order.map { index in
            guard let e = entries[index] else {
                return ToolCallBlock(id: "call-\(index)", name: "unknown", arguments: "{}")
            }
            return ToolCallBlock(id: e.id ?? "call-\(index)",
                                 name: e.name ?? "unknown",
                                 arguments: e.arguments.isEmpty ? "{}" : e.arguments)
        }
    }
}

// MARK: - 错误类型

public enum LLMError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case networkError(String)
    case decodingError(String)
    case emptyResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 API Key，请先到「设置 → 模型服务」中填写。"
        case let .httpError(status, body):
            let hint = switch status {
            case 401: "API Key 无效或已过期"
            case 402: "账户余额不足"
            case 403: "无权限访问该模型"
            case 404: "模型不存在或接口地址错误"
            case 429: "请求频率超限，请稍后重试"
            case 500 ... 599: "服务端错误，请稍后重试"
            default: ""
            }
            return "请求失败 (HTTP \(status))\(hint.isEmpty ? "" : "：\(hint)")\n\(body)"
        case let .networkError(m):
            return "网络错误：\(m)（请检查本地服务是否启动 / 网络连通性）"
        case let .decodingError(m):
            return "响应解析失败：\(m)"
        case .emptyResponse:
            return "模型返回了空内容"
        case .cancelled:
            return "已取消"
        }
    }
}
