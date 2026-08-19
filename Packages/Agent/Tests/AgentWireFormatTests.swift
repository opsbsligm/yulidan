@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - Wire 格式桩（独立 URLProtocol，按 FIFO 返回预设 wire 响应体，并捕获全部请求体）

/// 专用 wire 桩：验证 AgentLoop → LLMProvider → OpenAI 兼容 wire 的完整工具循环链路
final class WireStubURLProtocol: URLProtocol {
    static let lock = NSLock()
    nonisolated(unsafe) static var queue: [String] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func reset() {
        lock.lock()
        queue = []
        bodies = []
        lock.unlock()
    }

    static func enqueue(_ body: String) {
        lock.lock()
        queue.append(body)
        lock.unlock()
    }

    static func bodiesJSON() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return bodies.compactMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        if let body = Self.readBody(of: request) {
            Self.bodies.append(body)
        }
        let canned: String = if !Self.queue.isEmpty {
            Self.queue.removeFirst()
        } else {
            #"{"error":"wire stub queue empty"}"#
        }
        Self.lock.unlock()
        guard let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: LLMError.networkError("wire stub 构造响应失败"))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(canned.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// 基于真实 OpenAICompatChat（桩 session）的 LLMProvider — 请求/响应全走 wire 格式
final class WireFormatStubProvider: LLMProvider, @unchecked Sendable {
    let id = "wire-stub"
    let supportedModels: [String] = ["wire-model"]
    let profile = ProviderProfile.openAI

    private let chat: OpenAICompatChat
    private let lock = NSLock()
    private var _count = 0

    var callCount: Int {
        lock.withLock { _count }
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WireStubURLProtocol.self]
        chat = OpenAICompatChat(apiKey: "k",
                                baseURL: URL(string: "http://wire.local/v1")!,
                                session: URLSession(configuration: config))
    }

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        lock.withLock { _count += 1 }
        let result = try await chat.complete(model: request.model,
                                             messages: request.messages,
                                             systemPrompt: request.systemPrompt,
                                             tools: request.tools,
                                             maxTokens: request.maxTokens,
                                             temperature: request.temperature)
        return LLMResponseNormalizer.response(model: request.model, result: result, profile: profile)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// 最小测试工具：回显 text 参数
struct WireEchoTool: Tool {
    let name = "wire_echo"
    let description = "回显文本"
    let parameterSchema = #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#
    var requiredParameters: [String] {
        ["text"]
    }

    func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text("echo: \(args["text"] ?? "")")])
    }
}

// MARK: - AgentLoop + 真实 wire 格式端到端工具循环

@Suite("AgentLoop wire 格式端到端（模块8 多模型归一）", .serialized)
struct AgentWireFormatTests {
    /// 第 1 次响应：wire tool_calls
    private static let toolCallBody = """
    {"id":"cmpl-1","object":"chat.completion","model":"wire-model",
    "choices":[{"message":{"role":"assistant","content":null,
    "tool_calls":[{"id":"call_w1","type":"function","function":{"name":"wire_echo","arguments":"{\\"text\\":\\"ping-wire\\"}"}}]},
    "finish_reason":"tool_calls"}],
    "usage":{"prompt_tokens":5,"completion_tokens":5,"total_tokens":10}}
    """

    /// 第 2 次响应：最终文本
    private static let finalBody = """
    {"id":"cmpl-2","object":"chat.completion","model":"wire-model",
    "choices":[{"message":{"role":"assistant","content":"wire-e2e-done"},"finish_reason":"stop"}],
    "usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}
    """

    @Test("工具循环全链路：tools 下发 → tool_calls 解析 → 工具执行 → 结果回填 → 收敛")
    func wireToolLoop() async {
        WireStubURLProtocol.reset()
        WireStubURLProtocol.enqueue(Self.toolCallBody)
        WireStubURLProtocol.enqueue(Self.finalBody)

        let provider = WireFormatStubProvider()
        let tools = ToolRegistry()
        await tools.register(WireEchoTool())
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(),
                             llm: provider, tools: tools, model: "wire-model")

        await loop.send(UserMessage(content: [.text("回显 ping-wire")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)

        #expect(result.error == nil)
        #expect(provider.callCount == 2)

        var finalText = ""
        if let first = result.messages.first, let block = first.content.first, case let .text(t) = block {
            finalText = t
        }
        #expect(finalText == "wire-e2e-done")

        // 工具真实执行且无错
        let toolResults = await loop.allToolResults
        #expect(toolResults.count == 1)
        let first = toolResults.first
        #expect(first?.error == nil)
        #expect(first.map { AgentLoop.text(from: $0.content).contains("ping-wire") } == true)

        // 请求体断言（OpenAI wire 格式）
        let bodies = WireStubURLProtocol.bodiesJSON()
        #expect(bodies.count == 2)
        // 第 1 次：tools 下发
        if bodies.count >= 1, let toolsArr = bodies[0]["tools"] as? [[String: Any]] {
            #expect(toolsArr.contains { ($0["function"] as? [String: Any])?["name"] as? String == "wire_echo" })
        } else {
            Issue.record("第 1 次请求体应包含 tools 下发")
        }
        // 第 2 次：历史含 assistant tool_calls 与 role:"tool" 结果回填
        if bodies.count >= 2, let msgs = bodies[1]["messages"] as? [[String: Any]] {
            let assistant = msgs.first { ($0["role"] as? String) == "assistant" }
            #expect((assistant?["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == "call_w1")
            let toolMsg = msgs.first { ($0["role"] as? String) == "tool" }
            #expect(toolMsg?["tool_call_id"] as? String == "call_w1")
            #expect((toolMsg?["content"] as? String)?.contains("echo: ping-wire") == true)
        } else {
            Issue.record("第 2 次请求体应包含工具调用历史")
        }
    }

    @Test("纯文本回答：单次 wire 调用收敛")
    func wireTextOnly() async {
        WireStubURLProtocol.reset()
        WireStubURLProtocol.enqueue(Self.finalBody)

        let provider = WireFormatStubProvider()
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(),
                             llm: provider, tools: ToolRegistry(), model: "wire-model")
        await loop.send(UserMessage(content: [.text("你好")]), target: .nextTurn, wakeup: true)
        let result = await awaitTurnResult(loop)
        #expect(result.error == nil)
        #expect(provider.callCount == 1)
    }
}
