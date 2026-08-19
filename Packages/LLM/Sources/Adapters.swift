import Foundation

// MARK: - OpenAI 家族共享实现（OpenAI / DeepSeek / Local 均走 OpenAI 兼容协议）

private enum OpenAICompatAdapters {
    /// 非流式：下发 tools → 解析 tool_calls/reasoning/finish_reason → 归一化为统一 LLMResponse
    static func request(_ request: LLMRequest, chat: OpenAICompatChat, profile: ProviderProfile) async throws -> LLMResponse {
        let result = try await chat.complete(model: request.model,
                                             messages: request.messages,
                                             systemPrompt: request.systemPrompt,
                                             tools: request.tools,
                                             maxTokens: request.maxTokens,
                                             temperature: request.temperature)
        return LLMResponseNormalizer.response(model: request.model, result: result, profile: profile)
    }

    /// 流式：文本增量 → "text" 块；终态 → "message_complete" 块（finish_reason/usage/聚合 tool_calls）
    static func stream(_ request: LLMRequest, chat: OpenAICompatChat) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = 0
                    var finishReason: LLMResponse.FinishReason = .stop
                    var usage: TokenUsage?
                    var toolCalls: [LLM.ToolCallBlock] = []
                    for try await event in chat.streamEvents(model: request.model,
                                                             messages: request.messages,
                                                             systemPrompt: request.systemPrompt,
                                                             tools: request.tools,
                                                             maxTokens: request.maxTokens,
                                                             temperature: request.temperature) {
                        switch event {
                        case let .text(t):
                            if let data = t.data(using: .utf8) {
                                continuation.yield(StreamChunk(type: "text", data: data, index: index))
                                index += 1
                            }
                        case let .done(finish, usage: u, toolCalls: calls):
                            finishReason = finish
                            usage = u
                            toolCalls = calls
                        }
                    }
                    let summary: [String: Any] = [
                        "finish_reason": finishReason.rawValue,
                        "usage": usage.map {
                            ["prompt_tokens": $0.promptTokens,
                             "completion_tokens": $0.completionTokens,
                             "total_tokens": $0.totalTokens]
                        } ?? NSNull(),
                        "tool_calls": toolCalls.map {
                            ["id": $0.id, "name": $0.name, "arguments": $0.arguments]
                        },
                    ]
                    let payload = (try? JSONSerialization.data(withJSONObject: summary)) ?? Data()
                    continuation.yield(StreamChunk(type: "message_complete", data: payload, index: index))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI 适配器（真实 HTTP 实现）

public struct OpenAIAdapter: LLMProvider {
    public let id = "openai"
    public let supportedModels: [String] = ["gpt-4o", "gpt-4o-mini", "o3", "o4-mini"]
    public let profile = ProviderProfile.openAI

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        try await OpenAICompatAdapters.request(request,
                                               chat: OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session),
                                               profile: profile)
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        OpenAICompatAdapters.stream(request,
                                    chat: OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session))
    }

    public func checkConnection() async throws -> String {
        try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session).checkConnection()
    }
}

// MARK: - DeepSeek 适配器（真实 HTTP 实现，OpenAI 兼容协议）

public struct DeepSeekAdapter: LLMProvider {
    public let id = "deepseek"
    public let supportedModels: [String] = ["deepseek-chat", "deepseek-reasoner"]
    public let profile = ProviderProfile.deepSeek

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.deepseek.com/v1")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        try await OpenAICompatAdapters.request(request,
                                               chat: OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session),
                                               profile: profile)
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        OpenAICompatAdapters.stream(request,
                                    chat: OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session))
    }

    public func checkConnection() async throws -> String {
        try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session).checkConnection()
    }
}

// MARK: - 本地模型适配器（Ollama / vLLM / LM Studio，OpenAI 兼容协议）

public struct LocalAdapter: LLMProvider {
    public let id = "local"
    public let supportedModels: [String] = ["local"]
    public let profile = ProviderProfile.local

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    /// 默认指向 Ollama 的 OpenAI 兼容端点
    public init(apiKey: String = "ollama",
                baseURL: URL = URL(string: "http://localhost:11434/v1")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    private var chat: OpenAICompatChat {
        OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session)
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        try await OpenAICompatAdapters.request(request, chat: chat, profile: profile)
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        OpenAICompatAdapters.stream(request, chat: chat)
    }

    public func checkConnection() async throws -> String {
        try await chat.checkConnection()
    }
}

// MARK: - Anthropic 适配器（messages 协议，tools 用 input_schema）

public struct AnthropicAdapter: LLMProvider {
    public let id = "anthropic"
    public let supportedModels: [String] = ["claude-3-5-haiku-20241022", "claude-3-5-sonnet-20241022", "claude-sonnet-4-20250514"]
    public let profile = ProviderProfile.anthropic

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    /// 消息可序列化部分（文本 / 工具调用 / 工具结果）
    private struct AnthMsgParts {
        let text: String
        let toolCalls: [LLM.ToolCallBlock]
        let toolResults: [(id: String, text: String)]
    }

    private static func classify(_ m: Message) -> AnthMsgParts {
        var textParts: [String] = []
        var toolCalls: [LLM.ToolCallBlock] = []
        var toolResults: [(id: String, text: String)] = []
        for block in m.content {
            switch block {
            case let .text(t):
                if !t.isEmpty {
                    textParts.append(t)
                }
            case let .toolCall(tc):
                toolCalls.append(tc)
            case let .toolResult(tr):
                let contentText = tr.content.compactMap { b -> String? in
                    if case let .text(t) = b {
                        return t
                    }
                    return nil
                }.joined(separator: "\n")
                toolResults.append((tr.toolCallId, contentText))
            case .reasoning, .image:
                break
            }
        }
        return AnthMsgParts(text: textParts.joined(separator: "\n"), toolCalls: toolCalls, toolResults: toolResults)
    }

    /// Anthropic 无独立 system 槽位的历史消息序列化：
    /// - system 消息并入 system 字段
    /// - assistant toolCall → content 块数组 [{type:"tool_use", id, name, input}]
    /// - tool 结果 → user 消息 content 块数组 [{type:"tool_result", tool_use_id, content}]
    private func buildMessages(_ messages: [Message], systemPrompt: String?) -> (String?, [AnthMsg]) {
        var system = systemPrompt
        var out: [AnthMsg] = []
        for m in messages {
            let parts = Self.classify(m)
            switch m.role {
            case .system:
                if !parts.text.isEmpty {
                    system = system.map { $0 + "\n" + parts.text } ?? parts.text
                }
            case .assistant:
                if let msg = Self.assistantMsg(parts) {
                    out.append(msg)
                }
            case .tool, .user:
                if let msg = Self.userMsg(parts) {
                    out.append(msg)
                }
            }
        }
        return (system, out)
    }

    /// assistant 消息：纯文本或 tool_use 块数组
    private static func assistantMsg(_ parts: AnthMsgParts) -> AnthMsg? {
        if parts.toolCalls.isEmpty {
            return parts.text.isEmpty ? nil : AnthMsg(role: "assistant", content: .text(parts.text))
        }
        var blocks: [AnthContentBlockDTO] = []
        if !parts.text.isEmpty {
            blocks.append(AnthContentBlockDTO(text: parts.text))
        }
        for tc in parts.toolCalls {
            blocks.append(AnthContentBlockDTO(toolUse: AnthToolUseDTO(id: tc.id,
                                                                      name: tc.name,
                                                                      input: JSONValue(jsonString: tc.arguments))))
        }
        return AnthMsg(role: "assistant", content: .blocks(blocks))
    }

    /// user/tool 消息：纯文本或 tool_result 块数组
    private static func userMsg(_ parts: AnthMsgParts) -> AnthMsg? {
        if parts.toolResults.isEmpty {
            return parts.text.isEmpty ? nil : AnthMsg(role: "user", content: .text(parts.text))
        }
        var blocks: [AnthContentBlockDTO] = parts.toolResults.map {
            AnthContentBlockDTO(toolUseId: $0.id, content: $0.text)
        }
        if !parts.text.isEmpty {
            blocks.append(AnthContentBlockDTO(text: parts.text))
        }
        return AnthMsg(role: "user", content: .blocks(blocks))
    }

    /// Anthropic stop_reason → 统一 FinishReason
    public static func mapStopReason(_ raw: String?) -> LLMResponse.FinishReason {
        switch raw {
        case "tool_use"?:
            .toolCalls
        case "max_tokens"?:
            .length
        case "end_turn"?, "stop_sequence"?, nil:
            .stop
        default:
            .stop
        }
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let url = baseURL.appendingPathComponent("messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (system, msgs) = buildMessages(request.messages, systemPrompt: request.systemPrompt)
        var body = AnthRequest(model: request.model,
                               maxTokens: request.maxTokens ?? profile.defaultMaxTokens ?? 4096,
                               system: system,
                               messages: msgs)
        if let tools = request.tools, !tools.isEmpty {
            body.tools = tools.map(AnthToolDTO.init)
        }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("无法解析 HTTP 响应")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(status: http.statusCode, body: String(msg.prefix(500)))
        }
        do {
            let r = try JSONDecoder().decode(AnthResponseDTO.self, from: data)
            let text = r.content.compactMap(\.text).joined()
            let toolCalls = r.content.enumerated().compactMap { i, block -> LLM.ToolCallBlock? in
                guard block.type == "tool_use" else { return nil }
                let arguments = String(data: block.input?.jsonData() ?? Data(), encoding: .utf8)
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "{}"
                return LLM.ToolCallBlock(id: block.id ?? "toolu-\(i)",
                                         name: block.name ?? "unknown",
                                         arguments: arguments)
            }
            let usage = r.usage.map {
                TokenUsage(promptTokens: $0.inputTokens ?? 0,
                           completionTokens: $0.outputTokens ?? 0,
                           totalTokens: ($0.inputTokens ?? 0) + ($0.outputTokens ?? 0))
            }
            let result = CompletionResult(content: text,
                                          reasoning: nil,
                                          toolCalls: toolCalls,
                                          finishReason: Self.mapStopReason(r.stopReason),
                                          usage: usage)
            return LLMResponseNormalizer.response(model: request.model, result: result, profile: profile)
        } catch let e as LLMError {
            throw e
        } catch {
            throw LLMError.decodingError("响应解析失败: \(error.localizedDescription)")
        }
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        // Anthropic 流式协议较复杂，当前版本回退为非流式，将完整响应作为单个块返回
        let response = try await self.request(request)
        let text = response.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined()
        let summary: [String: Any] = [
            "id": response.id,
            "model": response.model,
            "content": text,
            "finish_reason": response.finishReason.rawValue,
            "tool_calls": (response.toolCalls ?? []).map {
                ["id": $0.id, "name": $0.name, "arguments": $0.arguments]
            },
        ]
        let payload = (try? JSONSerialization.data(withJSONObject: summary)) ?? Data()
        return AsyncThrowingStream { continuation in
            continuation.yield(StreamChunk(type: "message_complete", data: payload, index: 0))
            continuation.finish()
        }
    }

    public func checkConnection() async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        // 用小 max_tokens 发一次真实请求验证 Key
        let resp = try await request(LLMRequest(
            model: "claude-3-5-haiku-20241022",
            messages: [Message(role: .user, content: [.text("ping")])],
            maxTokens: 1
        ))
        _ = resp
        return "连接成功"
    }
}

// MARK: - Anthropic 响应 DTO（文件级，避免局部类型嵌套过深；驼峰 + CodingKeys 对齐 wire 格式）

/// Anthropic 响应内容块（text / tool_use）
private struct AnthResponseBlockDTO: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: JSONValue?
}

/// Anthropic usage 计数
private struct AnthUsageDTO: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// Anthropic messages 响应
private struct AnthResponseDTO: Decodable {
    let content: [AnthResponseBlockDTO]
    let usage: AnthUsageDTO?
    let stopReason: String?
    enum CodingKeys: String, CodingKey {
        case content, usage
        case stopReason = "stop_reason"
    }
}

// MARK: - Anthropic 请求 DTO（文件作用域，private 仅供本文件使用）

/// Anthropic 消息内容 — wire 上可以是纯字符串或内容块数组（工具调用历史）
private enum AnthContent: Encodable {
    case text(String)
    case blocks([AnthContentBlockDTO])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(s):
            try container.encode(s)
        case let .blocks(b):
            try container.encode(b)
        }
    }
}

/// Anthropic 请求消息
private struct AnthMsg: Encodable {
    let role: String
    let content: AnthContent
}

/// 内容块（text / tool_use / tool_result 三形态，字段平铺对齐 wire 格式）
private struct AnthContentBlockDTO: Encodable {
    let type: String
    let text: String?
    let content: String?
    let id: String?
    let name: String?
    let input: JSONValue?
    let toolUseId: String?
    enum CodingKeys: String, CodingKey {
        case type, text, content, id, name, input
        case toolUseId = "tool_use_id"
    }

    init(text: String) {
        type = "text"
        self.text = text
        content = nil
        id = nil
        name = nil
        input = nil
        toolUseId = nil
    }

    init(toolUse: AnthToolUseDTO) {
        type = "tool_use"
        text = nil
        content = nil
        id = toolUse.id
        name = toolUse.name
        input = toolUse.input
        toolUseId = nil
    }

    init(toolUseId: String, content: String) {
        type = "tool_result"
        text = nil
        self.content = content
        id = nil
        name = nil
        input = nil
        self.toolUseId = toolUseId
    }
}

private struct AnthToolUseDTO: Encodable {
    let id: String
    let name: String
    let input: JSONValue
}

/// tools 下发条目：{name, description, input_schema}
private struct AnthToolDTO: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }

    init(_ schema: ToolSchema) {
        name = schema.name
        description = schema.description
        inputSchema = JSONValue(jsonString: schema.parameters)
    }
}

/// Anthropic messages 请求体
private struct AnthRequest: Encodable {
    var model: String
    var maxTokens: Int
    var system: String?
    var messages: [AnthMsg]
    var tools: [AnthToolDTO]?
    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case maxTokens = "max_tokens"
    }
}
