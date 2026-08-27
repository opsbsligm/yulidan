import Foundation

// MARK: - Ollama 原生 API 客户端（/api/chat）

//
// 背景（2026-08-27 实机实证）：OpenAI 兼容端点 /v1/chat/completions **不受理** options 字段——
// 下发 num_ctx=32768 被忽略（runner 仍以 -c 4096 加载；官方兼容端点字段清单亦无 options）。
// 仅原生 /api/chat 的 options.num_ctx（官方文档在案）能真实控制本地模型上下文窗口。
// 因此 LocalAdapter 探测引擎为 Ollama 时走本客户端；vLLM / LM Studio 继续走 OpenAI 兼容路径。
//
// 协议要点（官方文档 /api/chat）：
// - 请求：messages（role/content/tool_calls；tool_calls.arguments 为 **JSON 对象**，非 OpenAI 的字符串）
// - 请求：options.num_ctx（上下文窗口）/ options.num_predict（生成上限）
// - 请求：think（思考模型顶层字段，布尔或 "low"/"medium"/"high"/"max"）
// - 请求：tool 结果消息须带 tool_name（所调用函数名，官方文档示例）
// - 响应（流式）：NDJSON（每行一个 JSON 对象，非 SSE）；message.thinking = 推理过程
// - 响应：done_reason（stop / length / context_overflow / prompt_too_long / abort / error_*）
// - 响应：prompt_eval_count / eval_count = 提示/生成 token 数

// MARK: - 请求侧 DTO（文件级 private，避免类型嵌套过深）

/// 原生函数引用（arguments 为 JSON 对象，非 OpenAI 的字符串）
private struct NatFunction: Encodable {
    let name: String
    let arguments: JSONValue
}

private struct NatToolCall: Encodable {
    let function: NatFunction
}

/// 原生请求消息（tool 结果消息须带 tool_name，官方文档示例）
private struct NatMsg: Encodable {
    let role: String
    let content: String?
    let toolCalls: [NatToolCall]?
    /// 官方 wire key：所调用函数名（tool_name）
    let toolName: String?
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }
}

private struct NatOptions: Encodable {
    let numCtx: Int?
    let numPredict: Int?
    enum CodingKeys: String, CodingKey {
        case numCtx = "num_ctx"
        case numPredict = "num_predict"
    }
}

private struct NatRequest: Encodable {
    let model: String
    let messages: [NatMsg]
    let tools: [ChatToolDTO]?
    let options: NatOptions?
    let think: String?
    let stream: Bool
}

// MARK: - 响应侧 DTO（文件级 private）

private struct NatRespFunction: Decodable {
    let name: String?
    let arguments: JSONValue?
}

private struct NatRespToolCall: Decodable {
    let function: NatRespFunction?
}

private struct NatRespMessage: Decodable {
    let role: String?
    let content: String?
    let thinking: String?
    let toolCalls: [NatRespToolCall]?
    enum CodingKeys: String, CodingKey {
        case role, content, thinking
        case toolCalls = "tool_calls"
    }
}

private struct NatResp: Decodable {
    let message: NatRespMessage?
    let done: Bool?
    let doneReason: String?
    let promptEvalCount: Int?
    let evalCount: Int?
    enum CodingKeys: String, CodingKey {
        case message, done
        case doneReason = "done_reason"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

// MARK: - 客户端

/// Ollama 原生 API 客户端 — /api/chat 非流式 + NDJSON 流式
public struct OllamaNativeChat: Sendable {
    /// 原生 base（不含 /v1 后缀；由 LocalAdapter 从 OpenAI 兼容地址剥离）
    public let baseURL: URL
    public var timeout: TimeInterval = 120
    public let session: URLSession

    public init(baseURL: URL, timeout: TimeInterval = 120, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    // MARK: - 请求构建

    /// 消息可序列化部分（文本 / 工具调用 / 工具结果）— 与 OpenAICompatChat.classify 同构
    private static func classify(_ m: Message) -> (text: [String], toolCalls: [ToolCallBlock], toolResults: [(id: String, text: String)]) {
        var text: [String] = []
        var tcs: [ToolCallBlock] = []
        var trs: [(id: String, text: String)] = []
        for block in m.content {
            switch block {
            case let .text(t) where !t.isEmpty:
                text.append(t)
            case let .toolCall(tc):
                tcs.append(tc)
            case let .toolResult(tr):
                let c = tr.content.compactMap { b -> String? in
                    if case let .text(t) = b {
                        return t
                    }
                    return nil
                }.joined(separator: "\n")
                trs.append((tr.toolCallId, c))
            default:
                break
            }
        }
        return (text, tcs, trs)
    }

    private static func wireMessages(_ m: Message, toolNames: [String: String]) -> [NatMsg] {
        let parts = classify(m)
        if m.role == .system {
            let joined = parts.text.joined(separator: "\n")
            return joined.isEmpty ? [] : [.init(role: "system", content: joined, toolCalls: nil, toolName: nil)]
        }
        if m.role == .assistant {
            if parts.toolCalls.isEmpty {
                return parts.text.isEmpty ? [] : [.init(role: "assistant", content: parts.text.joined(separator: "\n"), toolCalls: nil, toolName: nil)]
            }
            return [.init(role: "assistant",
                          content: parts.text.isEmpty ? nil : parts.text.joined(separator: "\n"),
                          toolCalls: parts.toolCalls.map { tc in
                              NatToolCall(function: .init(name: tc.name, arguments: JSONValue(jsonString: tc.arguments)))
                          },
                          toolName: nil)]
        }
        // user / tool：工具结果各成 {role:"tool", tool_name:函数名} 消息（官方文档格式）；纯文本按原角色下发
        var out: [NatMsg] = []
        for r in parts.toolResults {
            out.append(.init(role: "tool", content: r.text, toolCalls: nil, toolName: toolNames[r.id]))
        }
        if !parts.text.isEmpty {
            out.append(.init(role: m.role == .tool ? "tool" : "user", content: parts.text.joined(separator: "\n"), toolCalls: nil, toolName: nil))
        }
        return out
    }

    private func makeRequest(model: String,
                             messages: [Message],
                             systemPrompt: String? = nil,
                             tools: [ToolSchema]? = nil,
                             maxTokens: Int? = nil,
                             numCtx: Int? = nil,
                             think: String? = nil,
                             stream: Bool) throws -> URLRequest {
        // 预扫全历史建 tool_call id → 函数名映射（原生 tool 结果消息需 tool_name，官方文档在案）
        var toolNames: [String: String] = [:]
        for m in messages where m.role == .assistant {
            for tc in Self.classify(m).toolCalls where !tc.id.isEmpty {
                toolNames[tc.id] = tc.name
            }
        }
        var msgs: [NatMsg] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            msgs.append(.init(role: "system", content: systemPrompt, toolCalls: nil, toolName: nil))
        }
        for m in messages {
            msgs += Self.wireMessages(m, toolNames: toolNames)
        }
        var options: NatOptions?
        if numCtx != nil || maxTokens != nil {
            options = NatOptions(numCtx: numCtx, numPredict: maxTokens)
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            req.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        }
        let dto = NatRequest(model: model, messages: msgs, tools: tools?.map { ChatToolDTO($0) },
                             options: options, think: think, stream: stream)
        req.httpBody = try JSONEncoder().encode(dto)
        return req
    }

    // MARK: - 响应映射

    /// done_reason → FinishReason（官方取值：stop / length / context_overflow / prompt_too_long / abort / error_*）
    static func mapDoneReason(_ raw: String?) -> LLMResponse.FinishReason {
        switch raw {
        case "stop", "load":
            .stop
        case "length", "context_overflow", "prompt_too_long":
            .length
        case "tool_calls":
            .toolCalls
        default:
            .stop
        }
    }

    /// 原生 tool_calls（无 id 字段）→ 统一 ToolCallBlock（id 合成，与 OpenAI 路径缺省回退一致）
    private static func toolBlocks(from msg: NatRespMessage) -> [ToolCallBlock] {
        (msg.toolCalls ?? []).enumerated().map { i, tc in
            let args = tc.function?.arguments.flatMap { String(data: $0.jsonData(), encoding: .utf8) }
            return ToolCallBlock(id: "call-\(i)", name: tc.function?.name ?? "unknown", arguments: args ?? "{}")
        }
    }

    private static func usage(_ r: NatResp) -> TokenUsage? {
        guard r.promptEvalCount != nil || r.evalCount != nil else { return nil }
        let p = r.promptEvalCount ?? 0
        let c = r.evalCount ?? 0
        return TokenUsage(promptTokens: p, completionTokens: c, totalTokens: p + c)
    }

    // MARK: - 非流式

    public func complete(model: String,
                         messages: [Message],
                         systemPrompt: String? = nil,
                         tools: [ToolSchema]? = nil,
                         maxTokens: Int? = nil,
                         numCtx: Int? = nil,
                         think: String? = nil) async throws -> CompletionResult {
        let req = try makeRequest(model: model, messages: messages, systemPrompt: systemPrompt,
                                  tools: tools, maxTokens: maxTokens, numCtx: numCtx, think: think, stream: false)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("无法解析 HTTP 响应")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "(无响应体)"
            throw LLMError.httpError(status: http.statusCode, body: String(msg.prefix(500)))
        }
        let r: NatResp
        do {
            r = try JSONDecoder().decode(NatResp.self, from: data)
        } catch {
            throw LLMError.decodingError("响应解析失败: \(error.localizedDescription)")
        }
        let msg = r.message
        return CompletionResult(content: msg?.content ?? "",
                                reasoning: msg?.thinking.flatMap { $0.isEmpty ? nil : $0 },
                                toolCalls: msg.map { Self.toolBlocks(from: $0) } ?? [],
                                finishReason: Self.mapDoneReason(r.doneReason),
                                usage: Self.usage(r))
    }

    // MARK: - 流式（NDJSON）

    /// 单行 NDJSON 解码（空行/坏行返回 nil → 跳过）
    private static func decodeLine(_ line: String) -> NatResp? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NatResp.self, from: data)
    }

    /// 单行增量事件（thinking → reasoning；content → text）
    private static func lineEvents(of r: NatResp) -> [OpenAIStreamEvent] {
        guard let msg = r.message else { return [] }
        var events: [OpenAIStreamEvent] = []
        if let t = msg.thinking, !t.isEmpty {
            events.append(.reasoning(t))
        }
        if let c = msg.content, !c.isEmpty {
            events.append(.text(c))
        }
        return events
    }

    /// 单行携带的 tool_calls（出现即替换累计值）
    private static func lineToolCalls(of r: NatResp) -> [ToolCallBlock]? {
        guard let msg = r.message else { return nil }
        let calls = toolBlocks(from: msg)
        return calls.isEmpty ? nil : calls
    }

    public func streamEvents(model: String,
                             messages: [Message],
                             systemPrompt: String? = nil,
                             tools: [ToolSchema]? = nil,
                             maxTokens: Int? = nil,
                             numCtx: Int? = nil,
                             think: String? = nil) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try makeRequest(model: model, messages: messages, systemPrompt: systemPrompt,
                                              tools: tools, maxTokens: maxTokens, numCtx: numCtx, think: think, stream: true)
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
                    var toolCalls: [ToolCallBlock] = []
                    var usage: TokenUsage?
                    var finishReason: LLMResponse.FinishReason = .stop
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        guard let r = Self.decodeLine(line) else {
                            continue
                        }
                        for event in Self.lineEvents(of: r) {
                            continuation.yield(event)
                        }
                        if let calls = Self.lineToolCalls(of: r) {
                            toolCalls = calls
                        }
                        if r.done == true {
                            finishReason = Self.mapDoneReason(r.doneReason)
                            usage = Self.usage(r)
                        }
                    }
                    continuation.yield(.done(finishReason: finishReason, usage: usage, toolCalls: toolCalls))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
