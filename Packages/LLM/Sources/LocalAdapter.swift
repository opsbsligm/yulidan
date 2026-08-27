import Foundation

// MARK: - 本地模型适配器（Ollama / vLLM / LM Studio，OpenAI 兼容协议）

public struct LocalAdapter: LLMProvider {
    public let id = "local"
    public let supportedModels: [String] = ["local"]
    public let profile: ProviderProfile

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    /// 默认指向 Ollama 的 OpenAI 兼容端点；profile 可按模型名细分（ProviderProfile.local(forModel:)）
    public init(apiKey: String = "ollama",
                baseURL: URL = URL(string: "http://localhost:11434/v1")!,
                session: URLSession = .shared,
                profile: ProviderProfile = .local) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.profile = profile
    }

    private var chat: OpenAICompatChat {
        OpenAICompatChat(apiKey: apiKey, baseURL: baseURL, session: session)
    }

    /// 本地引擎识别：Ollama（原生 API，支持 options.num_ctx 真实控制上下文）/ 其他 OpenAI 兼容（vLLM / LM Studio）
    private enum Engine: Equatable { case ollamaNative, openAICompat }
    private final class EngineCache: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Engine?
        func get() -> Engine? {
            lock.withLock { value }
        }

        func set(_ e: Engine) {
            lock.withLock { value = e }
        }
    }

    private let engineCache = EngineCache()

    /// 原生 base（Ollama /api/* 不带 /v1 前缀）
    private var nativeBaseURL: URL {
        var c = baseURL
        if c.path.hasSuffix("/v1") {
            c.deleteLastPathComponent()
        }
        return c
    }

    /// 引擎探测（实例内缓存一次）：GET /api/tags 200 且含 models → Ollama；探测失败/非 Ollama → OpenAI 兼容（与旧行为一致）
    private func engine() async -> Engine {
        if let e = engineCache.get() {
            return e
        }
        var e: Engine = .openAICompat
        var req = URLRequest(url: nativeBaseURL.appendingPathComponent("api/tags"))
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["models"] != nil {
                e = .ollamaNative
            }
        } catch {
            // 探测失败（服务未起等）→ 维持 OpenAI 兼容路径，后续请求会暴露真实错误
        }
        engineCache.set(e)
        return e
    }

    /// 原生路径思考等级：Ollama 原生字段为顶层 think（布尔或 "low"/"medium"/"high"/"max"，官方文档）
    private func nativeThink(_ request: LLMRequest) -> String? {
        profile.supportsThinkingLevel ? request.thinkingLevel?.wireValue : nil
    }

    public func request(_ request: LLMRequest) async throws -> LLMResponse {
        switch await engine() {
        case .ollamaNative:
            // 上下文大小真实生效的唯一通道：原生 options.num_ctx（OpenAI 兼容端点不受理 options，08-27 实机实证）
            let result = try await OllamaNativeChat(baseURL: nativeBaseURL, session: session)
                .complete(model: request.model, messages: request.messages, systemPrompt: request.systemPrompt,
                          tools: request.tools, maxTokens: request.maxTokens, numCtx: request.numCtx,
                          think: nativeThink(request))
            return LLMResponseNormalizer.response(model: request.model, result: result, profile: profile)
        case .openAICompat:
            // vLLM / LM Studio：不支持按请求上下文大小 → 不下发 numCtx（UI 已标注）
            return try await OpenAICompatAdapters.request(request, chat: chat, profile: profile)
        }
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        switch await engine() {
        case .ollamaNative:
            streamEventsToChunks(OllamaNativeChat(baseURL: nativeBaseURL, session: session)
                .streamEvents(model: request.model, messages: request.messages, systemPrompt: request.systemPrompt,
                              tools: request.tools, maxTokens: request.maxTokens, numCtx: request.numCtx,
                              think: nativeThink(request)))
        case .openAICompat:
            OpenAICompatAdapters.stream(request, chat: chat, profile: profile)
        }
    }

    public func checkConnection() async throws -> String {
        try await chat.checkConnection()
    }
}

/// OpenAIStreamEvent → StreamChunk（text / reasoning / message_complete 终态）统一转换
/// — OpenAI 兼容与 Ollama 原生流式共用，保证上层 AgentLoop 消费契约一致
func streamEventsToChunks(_ events: AsyncThrowingStream<OpenAIStreamEvent, Error>) -> AsyncThrowingStream<LLM.StreamChunk, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var index = 0
                var finishReason: LLMResponse.FinishReason = .stop
                var usage: TokenUsage?
                var toolCalls: [LLM.ToolCallBlock] = []
                for try await event in events {
                    switch event {
                    case let .text(t):
                        if let data = t.data(using: .utf8) {
                            continuation.yield(StreamChunk(type: "text", data: data, index: index))
                            index += 1
                        }
                    case let .reasoning(r):
                        if let data = r.data(using: .utf8) {
                            continuation.yield(StreamChunk(type: "reasoning", data: data, index: index))
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
