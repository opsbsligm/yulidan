import Foundation
import LLM
import Testing
import XCTest

// MARK: - URLProtocol 桩（零真实网络）

/// 按 URL/请求头返回预设响应的 URLProtocol；同时捕获最后一次请求体供断言
final class StubURLProtocol: URLProtocol {
    struct Canned {
        let status: Int
        let body: String
        let contentType: String
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Canned)?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = StubURLProtocol.readBody(of: request)
        let canned = Self.handler?(request) ?? Canned(status: 599, body: "stub 未配置", contentType: "application/json")
        guard let response = HTTPURLResponse(url: request.url!, statusCode: canned.status,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": canned.contentType]) else {
            client?.urlProtocol(self, didFailWithError: LLMError.networkError("stub 构造响应失败"))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(canned.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession 可能把 httpBody 转成 httpBodyStream，两条路都要读
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

/// 带桩协议的测试 session
func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private let okCompletion = """
{"id":"cmpl-1","object":"chat.completion","model":"test-model","choices":[{"message":{"role":"assistant","content":"你好，世界"},"finish_reason":"stop"}],
"usage":{"prompt_tokens":5,"completion_tokens":7,"total_tokens":12}}
"""

private let sseBody = """
data: {"choices":[{"message":{"role":"assistant","content":"你"}}]}

data: {"choices":[{"message":{"role":"assistant","content":"好"}}]}

data: [DONE]

"""

private let anthropicBody = """
{"id":"msg_1","content":[{"type":"text","text":"来自 Anthropic"}],"usage":{"input_tokens":3,"output_tokens":4}}
"""

// MARK: - OpenAICompatChat HTTP 层

final class OpenAICompatChatHTTPTests: XCTestCase {
    private let base = URL(string: "http://stub.local/v1")!

    private func client(_ session: URLSession = makeStubSession()) -> OpenAICompatChat {
        OpenAICompatChat(apiKey: "test-key", baseURL: base, session: session)
    }

    override func setUp() {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    func testCompleteSuccessParsesContentAndUsage() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let (content, usage) = try await client().complete(model: "test-model",
                                                           messages: [Message(role: .user, content: [.text("hi")])])
        XCTAssertEqual(content, "你好，世界")
        XCTAssertEqual(usage?.totalTokens, 12)
        // 请求头/方法校验
        let req = StubURLProtocol.lastRequest!
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertTrue(req.url!.absoluteString.hasSuffix("/chat/completions"))
    }

    func testCompleteMissingKeyThrows() async {
        let empty = OpenAICompatChat(apiKey: "", baseURL: base, session: makeStubSession())
        do {
            _ = try await empty.complete(model: "m", messages: [Message(role: .user, content: [.text("hi")])])
            XCTFail("应当抛出 missingAPIKey")
        } catch let e as LLMError {
            guard case .missingAPIKey = e else {
                return XCTFail("错误类型不符：\(e)")
            }
        } catch {
            XCTFail("意外错误：\(error)")
        }
    }

    func testCompleteHttpErrorCarriesStatusAndHint() async {
        StubURLProtocol.handler = { _ in .init(status: 401, body: "{\"error\":\"invalid key\"}", contentType: "application/json") }
        do {
            _ = try await client().complete(model: "m", messages: [Message(role: .user, content: [.text("hi")])])
            XCTFail("应当抛出 httpError")
        } catch let e as LLMError {
            guard case let .httpError(status, body) = e else {
                return XCTFail("错误类型不符：\(e)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("invalid key"))
            XCTAssertTrue(e.errorDescription!.contains("API Key 无效或已过期"))
        } catch {
            XCTFail("意外错误：\(error)")
        }
    }

    func testCompleteBadJSONThrowsDecodingError() async {
        StubURLProtocol.handler = { _ in .init(status: 200, body: "这不是 JSON", contentType: "application/json") }
        do {
            _ = try await client().complete(model: "m", messages: [Message(role: .user, content: [.text("hi")])])
            XCTFail("应当抛出 decodingError")
        } catch let e as LLMError {
            guard case .decodingError = e else {
                return XCTFail("错误类型不符：\(e)")
            }
        } catch {
            XCTFail("意外错误：\(error)")
        }
    }

    func testCompleteEmptyChoicesThrowsEmptyResponse() async {
        StubURLProtocol.handler = { _ in .init(status: 200, body: #"{"choices":[]}"#, contentType: "application/json") }
        do {
            _ = try await client().complete(model: "m", messages: [Message(role: .user, content: [.text("hi")])])
            XCTFail("应当抛出 emptyResponse")
        } catch let e as LLMError {
            guard case .emptyResponse = e else {
                return XCTFail("错误类型不符：\(e)")
            }
        } catch {
            XCTFail("意外错误：\(error)")
        }
    }

    func testStreamYieldsSSEChunks() async throws {
        StubURLProtocol.handler = { req in
            req.value(forHTTPHeaderField: "Accept") == "text/event-stream"
                ? .init(status: 200, body: sseBody, contentType: "text/event-stream")
                : .init(status: 200, body: okCompletion, contentType: "application/json")
        }
        var collected = ""
        for try await chunk in client().stream(model: "m", messages: [Message(role: .user, content: [.text("hi")])]) {
            collected += chunk
        }
        XCTAssertEqual(collected, "你好")
        // 流式请求体必须带 stream: true
        let body = String(data: StubURLProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"stream\":true") || body.contains("\"stream\": true"))
    }

    func testStreamHttpErrorPropagates() async {
        StubURLProtocol.handler = { _ in .init(status: 500, body: "server boom", contentType: "text/event-stream") }
        do {
            for try await _ in client().stream(model: "m", messages: [Message(role: .user, content: [.text("hi")])]) {
                break
            }
            XCTFail("应当抛出 httpError")
        } catch let e as LLMError {
            guard case let .httpError(status, _) = e else {
                return XCTFail("错误类型不符：\(e)")
            }
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("意外错误：\(error)")
        }
    }

    func testCheckConnection() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: #"{"data":[]}"#, contentType: "application/json") }
        let result = try await client().checkConnection()
        XCTAssertEqual(result, "连接成功")
        XCTAssertTrue(StubURLProtocol.lastRequest!.url!.absoluteString.hasSuffix("/models"))
    }

    func testSseDeltaTextEdgeCases() {
        XCTAssertEqual(OpenAICompatChat.sseDeltaText(from: #"data: {"choices":[{"message":{"content":"x"}}]}"#), "x")
        XCTAssertEqual(OpenAICompatChat.sseDeltaText(from: "data: [DONE]"), nil)
        XCTAssertEqual(OpenAICompatChat.sseDeltaText(from: ": keep-alive"), nil)
        XCTAssertEqual(OpenAICompatChat.sseDeltaText(from: "data: 垃圾数据"), nil)
    }
}

// MARK: - 适配器（注入桩 session 的端到端）

final class AdapterHTTPTests: XCTestCase {
    private let base = URL(string: "http://stub.local/v1")!

    override func setUp() {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    func testOpenAIAdapterRequest() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let resp = try await adapter.request(LLMRequest(model: "gpt-4o-mini",
                                                        messages: [Message(role: .user, content: [.text("hi")])]))
        let text = resp.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined()
        XCTAssertEqual(text, "你好，世界")
        XCTAssertEqual(resp.finishReason, .stop)
    }

    func testOpenAIAdapterStream() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: sseBody, contentType: "text/event-stream") }
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        var collected = ""
        for try await chunk in try await adapter.stream(LLMRequest(model: "gpt-4o-mini",
                                                                   messages: [Message(role: .user, content: [.text("hi")])])) {
            collected += String(data: chunk.data, encoding: .utf8) ?? ""
        }
        XCTAssertEqual(collected, "你好")
    }

    func testDeepSeekAdapterRequest() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let adapter = DeepSeekAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let resp = try await adapter.request(LLMRequest(model: "deepseek-chat",
                                                        messages: [Message(role: .user, content: [.text("hi")])]))
        XCTAssertEqual(resp.model, "deepseek-chat")
    }

    func testLocalAdapterRequest() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let adapter = LocalAdapter(baseURL: base, session: makeStubSession())
        let resp = try await adapter.request(LLMRequest(model: "llama3.1",
                                                        messages: [Message(role: .user, content: [.text("hi")])]))
        XCTAssertEqual(resp.model, "llama3.1")
    }

    func testAnthropicAdapterRequestParsesContentAndUsage() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "sk-ant", baseURL: base, session: makeStubSession())
        let resp = try await adapter.request(LLMRequest(model: "claude-3-5-haiku-20241022",
                                                        messages: [Message(role: .user, content: [.text("ping")])],
                                                        systemPrompt: "你是助手"))
        let text = resp.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined()
        XCTAssertEqual(text, "来自 Anthropic")
        XCTAssertEqual(resp.usage?.totalTokens, 7)
        // 请求头校验：x-api-key + anthropic-version
        let req = StubURLProtocol.lastRequest!
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testAnthropicAdapterSystemMergedIntoRequest() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .system, content: [.text("角色A")]),
                                                            Message(role: .user, content: [.text("你好")])],
                                                 systemPrompt: "角色B"))
        let body = String(data: StubURLProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(obj["system"] as? String, "角色B\n角色A")
        let msgs = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        // system 消息被合并进 system 字段后，messages 首条应为 user
        XCTAssertEqual(msgs.first?["role"] as? String, "user")
        XCTAssertEqual(msgs.count, 1)
    }

    func testAnthropicAdapterStreamFallsBackToSingleChunk() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        var chunks = 0
        for try await _ in try await adapter.stream(LLMRequest(model: "m",
                                                               messages: [Message(role: .user, content: [.text("hi")])])) {
            chunks += 1
        }
        XCTAssertEqual(chunks, 1)
    }

    func testAnthropicAdapterMissingKey() async {
        let adapter = AnthropicAdapter(apiKey: "", baseURL: base, session: makeStubSession())
        do {
            _ = try await adapter.request(LLMRequest(model: "m",
                                                     messages: [Message(role: .user, content: [.text("hi")])]))
            XCTFail("应当抛出 missingAPIKey")
        } catch let e as LLMError {
            guard case .missingAPIKey = e else {
                return XCTFail("错误类型不符：\(e)")
            }
        } catch {
            XCTFail("意外错误：\(error)")
        }
    }
}
