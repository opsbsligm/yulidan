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

    struct ChatMessageDTO: Encodable {
        let role: String
        let content: String
    }

    struct ChatRequestDTO: Encodable {
        let model: String
        let messages: [ChatMessageDTO]
        let max_tokens: Int?
        let temperature: Double?
    }

    /// 从 LLM.Message 数组提取纯文本对话
    static func flatMessages(_ messages: [Message], systemPrompt: String?) -> [ChatMessageDTO] {
        var out: [ChatMessageDTO] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            out.append(.init(role: "system", content: systemPrompt))
        }
        for m in messages {
            let text = m.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
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
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let body = ChatRequestDTO(
            model: model,
            messages: Self.flatMessages(messages, systemPrompt: systemPrompt),
            max_tokens: maxTokens,
            temperature: temperature
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("无法解析 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "(无响应体)"
            throw LLMError.httpError(status: http.statusCode, body: String(msg.prefix(500)))
        }
        struct Resp: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
                let finish_reason: String?
            }
            let choices: [Choice]
            let usage: Usage?
            struct Usage: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
                let total_tokens: Int?
            }
        }
        do {
            let r = try JSONDecoder().decode(Resp.self, from: data)
            guard let first = r.choices.first else {
                throw LLMError.emptyResponse
            }
            let usage = r.usage.map {
                TokenUsage(promptTokens: $0.prompt_tokens ?? 0,
                           completionTokens: $0.completion_tokens ?? 0,
                           totalTokens: $0.total_tokens ?? 0)
            }
            return (first.message.content ?? "", usage)
        } catch let e as LLMError {
            throw e
        } catch {
            throw LLMError.decodingError("响应解析失败: \(error.localizedDescription)")
        }
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
                    for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
                    let dto = ChatRequestDTO(
                        model: model,
                        messages: Self.flatMessages(messages, systemPrompt: systemPrompt),
                        max_tokens: maxTokens,
                        temperature: temperature
                    )
                    var payload = try JSONEncoder().encode(dto)
                    if let streamKey = try? JSONSerialization.data(withJSONObject: ["stream": true]) {
                        // 在 JSON 中注入 "stream": true
                        if var obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                            obj["stream"] = true
                            payload = try JSONSerialization.data(withJSONObject: obj)
                        }
                    }
                    req.httpBody = payload

                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.networkError("无法解析 HTTP 响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errBody = ""
                        for try await line in bytes.lines { errBody += line }
                        throw LLMError.httpError(status: http.statusCode, body: String(errBody.prefix(500)))
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        struct Delta: Decodable {
                            struct Choice: Decodable {
                                struct Msg: Decodable { let content: String? }
                                let message: Msg
                            }
                            let choices: [Choice]
                        }
                        if let data = payload.data(using: .utf8),
                           let d = try? JSONDecoder().decode(Delta.self, from: data),
                           let text = d.choices.first?.message.content, !text.isEmpty {
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
        guard (200..<300).contains(http.statusCode) else {
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
        case .httpError(let status, let body):
            let hint: String
            switch status {
            case 401: hint = "API Key 无效或已过期"
            case 402: hint = "账户余额不足"
            case 403: hint = "无权限访问该模型"
            case 404: hint = "模型不存在或接口地址错误"
            case 429: hint = "请求频率超限，请稍后重试"
            case 500...599: hint = "服务端错误，请稍后重试"
            default: hint = ""
            }
            return "请求失败 (HTTP \(status))\(hint.isEmpty ? "" : "：\(hint)")\n\(body)"
        case .networkError(let m):
            return "网络错误：\(m)（请检查本地服务是否启动 / 网络连通性）"
        case .decodingError(let m):
            return "响应解析失败：\(m)"
        case .emptyResponse:
            return "模型返回了空内容"
        case .cancelled:
            return "已取消"
        }
    }
}
