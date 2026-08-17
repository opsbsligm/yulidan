import Foundation

// MARK: - OpenAI 适配器（真实 HTTP 实现）

public struct OpenAIAdapter: LLMProvider {
    public let id = "openai"
    public let supportedModels: [String] = ["gpt-4o", "gpt-4o-mini", "o3", "o4-mini"]

    private let apiKey: String
    private let baseURL: URL

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        let (content, usage) = try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL)
            .complete(model: request.model, messages: request.messages,
                      systemPrompt: request.systemPrompt, maxTokens: request.maxTokens,
                      temperature: request.temperature)
        return LLMResponse(id: UUID().uuidString, model: request.model,
                           content: [.text(content)], usage: usage,
                           toolCalls: nil, finishReason: .stop)
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = 0
                    for try await chunk in OpenAICompatChat(apiKey: apiKey, baseURL: baseURL)
                        .stream(model: request.model, messages: request.messages,
                                systemPrompt: request.systemPrompt, maxTokens: request.maxTokens,
                                temperature: request.temperature) {
                        if let data = chunk.data(using: .utf8) {
                            continuation.yield(StreamChunk(type: "text", data: data, index: index))
                            index += 1
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func checkConnection() async throws -> String {
        try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL).checkConnection()
    }
}

// MARK: - DeepSeek 适配器（真实 HTTP 实现，OpenAI 兼容协议）

public struct DeepSeekAdapter: LLMProvider {
    public let id = "deepseek"
    public let supportedModels: [String] = ["deepseek-chat", "deepseek-reasoner"]

    private let apiKey: String
    private let baseURL: URL

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.deepseek.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        let (content, usage) = try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL)
            .complete(model: request.model, messages: request.messages,
                      systemPrompt: request.systemPrompt, maxTokens: request.maxTokens,
                      temperature: request.temperature)
        return LLMResponse(id: UUID().uuidString, model: request.model,
                           content: [.text(content)], usage: usage,
                           toolCalls: nil, finishReason: .stop)
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = 0
                    for try await chunk in OpenAICompatChat(apiKey: apiKey, baseURL: baseURL)
                        .stream(model: request.model, messages: request.messages,
                                systemPrompt: request.systemPrompt, maxTokens: request.maxTokens,
                                temperature: request.temperature) {
                        if let data = chunk.data(using: .utf8) {
                            continuation.yield(StreamChunk(type: "text", data: data, index: index))
                            index += 1
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func checkConnection() async throws -> String {
        try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL).checkConnection()
    }
}

// MARK: - 本地模型适配器（Ollama / vLLM / LM Studio，OpenAI 兼容协议）

public struct LocalAdapter: LLMProvider {
    public let id = "local"
    public let supportedModels: [String] = ["local"]

    private let apiKey: String
    private let baseURL: URL

    /// 默认指向 Ollama 的 OpenAI 兼容端点
    public init(apiKey: String = "ollama", baseURL: URL = URL(string: "http://localhost:11434/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        let (content, usage) = try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL)
            .complete(model: request.model, messages: request.messages,
                      systemPrompt: request.systemPrompt, maxTokens: request.maxTokens,
                      temperature: request.temperature)
        return LLMResponse(id: UUID().uuidString, model: request.model,
                           content: [.text(content)], usage: usage,
                           toolCalls: nil, finishReason: .stop)
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = 0
                    for try await chunk in OpenAICompatChat(apiKey: apiKey, baseURL: baseURL)
                        .stream(model: request.model, messages: request.messages,
                                systemPrompt: request.systemPrompt, maxTokens: request.maxTokens,
                                temperature: request.temperature) {
                        if let data = chunk.data(using: .utf8) {
                            continuation.yield(StreamChunk(type: "text", data: data, index: index))
                            index += 1
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 本地服务无需 Key，直接探测端点
    public func checkConnection() async throws -> String {
        try await OpenAICompatChat(apiKey: apiKey, baseURL: baseURL).checkConnection()
    }
}

// MARK: - Anthropic 适配器（真实 HTTP 实现，messages 协议）

public struct AnthropicAdapter: LLMProvider {
    public let id = "anthropic"
    public let supportedModels: [String] = ["claude-sonnet-4-20250514", "claude-3-5-haiku-20241022"]

    private let apiKey: String
    private let baseURL: URL

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    private func buildMessages(_ messages: [Message], systemPrompt: String?) -> (system: String?, msgs: [AnthMsg]) {
        var system = systemPrompt
        var out: [AnthMsg] = []
        for m in messages {
            let text = m.content.compactMap { block -> String? in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.joined(separator: "\n")
            if text.isEmpty {
                continue
            }
            // Anthropic 要求首条必须为 user；把 system 角色消息合并进 system 字段
            if m.role == .system, var s = system {
                s += "\n\(text)"
                system = s
            } else {
                out.append(AnthMsg(role: m.role == .system ? "user" : m.role.rawValue, content: text))
            }
        }
        if let s = system {
            out.insert(AnthMsg(role: "user", content: s), at: 0)
        }
        return (system, out)
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
        let body = AnthRequest(model: request.model,
                               maxTokens: request.maxTokens ?? 4096,
                               system: system,
                               messages: msgs)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
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
            let usage = r.usage.map {
                TokenUsage(promptTokens: $0.inputTokens ?? 0,
                           completionTokens: $0.outputTokens ?? 0,
                           totalTokens: ($0.inputTokens ?? 0) + ($0.outputTokens ?? 0))
            }
            return LLMResponse(id: UUID().uuidString, model: request.model,
                               content: [.text(text)], usage: usage,
                               toolCalls: nil, finishReason: .stop)
        } catch let e as LLMError {
            throw e
        } catch {
            throw LLMError.decodingError("响应解析失败: \(error.localizedDescription)")
        }
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        // Anthropic 流式协议较复杂，当前版本回退为非流式，将完整响应作为单个块返回
        let response = try await self.request(request)
        let summary: [String: Any] = [
            "id": response.id,
            "model": response.model,
            "content": response.content,
            "finish_reason": response.finishReason.rawValue,
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

/// Anthropic 响应内容块
private struct AnthResponseBlockDTO: Decodable {
    let type: String
    let text: String?
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
}

// MARK: - Anthropic 请求 DTO（文件作用域，private 仅供本文件使用）

/// Anthropic 请求消息
private struct AnthMsg: Encodable {
    let role: String
    let content: String
}

/// Anthropic messages 请求体
private struct AnthRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthMsg]
    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}
