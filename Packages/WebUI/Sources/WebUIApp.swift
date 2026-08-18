import Agent
import Foundation
import LLM
import ServiceContainer
import Session
import Tools

// MARK: - 错误

public enum WebUIError: Error, Sendable {
    /// 会话回合超过等待上限
    case chatTimeout
}

// MARK: - 应用层

/// Web UI 应用层：HTTP 路由 + Agent 会话管理（与 socket 无关，可独立单测）
///
/// 会话为进程内状态（服务重启后清空）；桌面端 GUI 的 SQLite 持久化不受影响。
public actor WebUIApp {
    /// 运行配置（LLM/工具通过工厂注入，测试可打桩）
    public struct Config: Sendable {
        public let llm: any LLMProvider
        public let toolFactory: @Sendable () -> [any Tool]
        public let model: String
        public let systemPrompt: String?
        public let maxSteps: Int
        /// 单次对话最长等待（秒）
        public let chatTimeout: TimeInterval

        public init(
            llm: any LLMProvider,
            toolFactory: @escaping @Sendable () -> [any Tool],
            model: String,
            systemPrompt: String? = nil,
            maxSteps: Int = 8,
            chatTimeout: TimeInterval = 300
        ) {
            self.llm = llm
            self.toolFactory = toolFactory
            self.model = model
            self.systemPrompt = systemPrompt
            self.maxSteps = maxSteps
            self.chatTimeout = chatTimeout
        }
    }

    private let config: Config
    private var loops: [String: AgentLoop] = [:]
    private var titles: [String: String] = [:]
    private var turns: [String: Int] = [:]
    private var created: [String: Date] = [:]

    public init(config: Config) {
        self.config = config
    }

    // MARK: - 路由

    /// 全部入站请求的入口
    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/"):
            .text(WebUIPage.html, contentType: "text/html; charset=utf-8")
        case ("GET", "/healthz"):
            .json(Data(#"{"status":"ok"}"#.utf8))
        case ("GET", "/api/sessions"):
            handleSessions()
        case ("POST", "/api/chat"):
            await handleChat(request)
        case ("GET", "/api/chat"), ("POST", "/"), ("POST", "/healthz"), ("POST", "/api/sessions"):
            .methodNotAllowed("use \(request.method == "GET" ? "POST" : "GET")")
        default:
            .notFound(message: "unknown route: \(request.method) \(request.path)")
        }
    }

    // MARK: - 会话列表

    private func handleSessions() -> HTTPResponse {
        let sorted = created.sorted { $0.value > $1.value }
        let items: [[String: Any]] = sorted.map { id, date in
            [
                "id": id,
                "title": titles[id] ?? "新会话",
                "turns": turns[id] ?? 0,
                "createdAt": date.ISO8601Format(),
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: items)) ?? Data("[]".utf8)
        return .json(data)
    }

    // MARK: - 对话

    private struct ChatPayload: Decodable {
        let sessionId: String?
        let message: String?
    }

    private func handleChat(_ request: HTTPRequest) async -> HTTPResponse {
        let payload: ChatPayload
        do {
            payload = try JSONDecoder().decode(ChatPayload.self, from: request.body)
        } catch {
            return .badRequest("invalid JSON body")
        }
        guard let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return .badRequest("message is required")
        }
        let sessionId = payload.sessionId ?? UUID().uuidString

        // 已知会话续聊；未知/新建会话现建 AgentLoop（进程内不持久化，重启后按新会话处理）
        let loop: AgentLoop
        if let existing = loops[sessionId] {
            loop = existing
        } else {
            loop = await makeLoop()
            loops[sessionId] = loop
            created[sessionId] = Date()
        }
        if titles[sessionId] == nil {
            titles[sessionId] = String(message.prefix(48))
        }

        await loop.followup(UserMessage(content: [.text(message)]))
        let result: AgentResult
        do {
            result = try await withChatTimeout(config.chatTimeout) {
                await loop.whenIdle()
            }
        } catch {
            let data = Data(#"{"sessionId":"\#(sessionId)","reply":"","error":"chat timed out"}"#.utf8)
            return .json(data, status: 504)
        }

        var reply = ""
        for block in result.messages.last?.content ?? [] {
            if case let .text(text) = block {
                if !reply.isEmpty {
                    reply += "\n"
                }
                reply += text
            }
        }
        turns[sessionId] = await loop.turnNumber

        var payload2: [String: Any] = ["sessionId": sessionId, "reply": reply]
        if let error = result.error {
            payload2["error"] = error
        }
        let data = (try? JSONSerialization.data(withJSONObject: payload2)) ?? Data("{}".utf8)
        return .json(data)
    }

    private func makeLoop() async -> AgentLoop {
        let tools = ToolRegistry()
        for tool in config.toolFactory() {
            await tools.register(tool)
        }
        return AgentLoop(
            id: AgentID(),
            sessionID: SessionID(),
            llm: config.llm,
            tools: tools,
            model: config.model,
            systemPrompt: config.systemPrompt,
            maxSteps: config.maxSteps
        )
    }

    /// 带超时地等待 Agent 空闲
    private func withChatTimeout(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> AgentResult) async throws -> AgentResult {
        try await withThrowingTaskGroup(of: AgentResult.self) { group in
            group.addTask { await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw WebUIError.chatTimeout
            }
            defer { group.cancelAll() }
            let first = try await group.next()
            guard let first else {
                throw WebUIError.chatTimeout
            }
            group.cancelAll()
            return first
        }
    }
}
