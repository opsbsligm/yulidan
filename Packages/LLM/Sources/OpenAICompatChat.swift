import Foundation

/// OpenAI 兼容 HTTP 客户端 — 同时服务于 OpenAI / DeepSeek / 本地 OpenAI 兼容服务 (Ollama、vLLM、LM Studio)
/// 实现非流式 request 与 SSE 流式 stream。
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

    /// 从 LLM.Message 数组提取纯文本对话
    private static func flatMessages(_ messages: [Message], systemPrompt: String?) -> [ChatMessageDTO] {
        var out: [ChatMessageDTO] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            out.append(.init(role: "system", content: systemPrompt))
        }
        for m in messages {
            let text = m.content.compactMap { block -> String? in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.joined(separator: "\n")
            if !text.isEmpty {
                out.append(.init(role: m.role.rawValue, content: text))
            }
        }
        return out
    }

    // MARK: - 非流式

    /// 发起一次完整的 chat completion 请求，返回 (content, usage)
    public func complete(model: String,
                         messages: [Message],
                         systemPrompt: String? = nil,
                         maxTokens: Int? = nil,
                         temperature: Double? = nil,
                         extraHeaders: [String: String] = [:]) async throws -> (content: String, usage: TokenUsage?) {
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        let url = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let body = ChatRequestDTO(
            model: model,
            messages: Self.flatMessages(messages, systemPrompt: systemPrompt),
            maxTokens: maxTokens,
            temperature: temperature
        )
        req.httpBody = try JSONEncoder().encode(body)

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

    /// 解析 chat/completions 响应为 (文本, usage)
    private static func parseCompletionResponse(_ data: Data) throws -> (content: String, usage: TokenUsage?) {
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
        let usage = r.usage.map {
            TokenUsage(promptTokens: $0.promptTokens ?? 0,
                       completionTokens: $0.completionTokens ?? 0,
                       totalTokens: $0.totalTokens ?? 0)
        }
        return (first.message.content ?? "", usage)
    }

    /// 解析单行 SSE 文本为增量内容；非 data: 行 / [DONE] / 解析失败返回 nil
    static func sseDeltaText(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let d = try? JSONDecoder().decode(ChatDeltaDTO.self, from: data),
              let text = d.choices.first?.message.content, !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: - SSE 流式

    /// 流式 chat completion，逐块 yield 增量文本
    public func stream(model: String,
                       messages: [Message],
                       systemPrompt: String? = nil,
                       maxTokens: Int? = nil,
                       temperature: Double? = nil,
                       extraHeaders: [String: String] = [:]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = baseURL.appendingPathComponent("chat/completions")
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = timeout
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    for (k, v) in extraHeaders {
                        req.setValue(v, forHTTPHeaderField: k)
                    }
                    let dto = ChatRequestDTO(
                        model: model,
                        messages: Self.flatMessages(messages, systemPrompt: systemPrompt),
                        maxTokens: maxTokens,
                        temperature: temperature
                    )
                    var payload = try JSONEncoder().encode(dto)
                    // 在请求体中注入 "stream": true
                    if var obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                        obj["stream"] = true
                        payload = try JSONSerialization.data(withJSONObject: obj)
                    }
                    req.httpBody = payload

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
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        // sseDeltaText 内部已处理 data: 前缀 / [DONE] / 解析失败
                        if let text = Self.sseDeltaText(from: line) {
                            continuation.yield(text)
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

// MARK: - OpenAI 兼容响应 DTO（文件级，避免局部类型嵌套过深；驼峰 + CodingKeys 对齐 wire 格式）

/// 助手消息内容
private struct ChatMessageContentDTO: Decodable {
    let content: String?
}

/// choices 条目
private struct ChatChoiceDTO: Decodable {
    let message: ChatMessageContentDTO
    let finishReason: String?
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

/// token 用量
private struct ChatUsageDTO: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

/// chat/completions 响应
private struct ChatCompletionRespDTO: Decodable {
    let choices: [ChatChoiceDTO]
    let usage: ChatUsageDTO?
}

// MARK: - OpenAI 兼容请求 DTO（文件作用域，private 仅供本文件使用）

/// chat/completions 请求消息
private struct ChatMessageDTO: Encodable {
    let role: String
    let content: String
}

/// chat/completions 请求体
private struct ChatRequestDTO: Encodable {
    let model: String
    let messages: [ChatMessageDTO]
    let maxTokens: Int?
    let temperature: Double?
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// SSE 单条 data: 增量（本客户端按 choices[].message.content 解析）
private struct ChatDeltaDTO: Decodable {
    let choices: [ChatChoiceDTO]
}
