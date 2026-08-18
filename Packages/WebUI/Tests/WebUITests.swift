import Agent
import Foundation
import LLM
import Testing
import WebUI

// MARK: - 桩 LLM

/// 回显桩：回复包含当前请求中的 user 消息数、最后一条 user 文本、累计调用次数（验证多轮上下文）
final class StubLLM: LLMProvider, @unchecked Sendable {
    let id = "stub"
    let supportedModels = ["stub-model"]
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        let total = lock.withLock {
            count += 1
            return count
        }
        let userMessages = request.messages.filter { $0.role == .user }
        var lastUser = ""
        for message in userMessages {
            for block in message.content {
                if case let .text(text) = block {
                    lastUser = text
                }
            }
        }
        return LLMResponse(model: "stub-model", content: [.text("echo[\(userMessages.count)]:\(lastUser)#\(total)")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        throw StubStreamError()
    }
}

struct StubStreamError: Error, Sendable {}

/// 慢速桩：延迟回答（用于 504 超时测试）
final class SlowStubLLM: LLMProvider, @unchecked Sendable {
    let id = "slow"
    let supportedModels = ["stub-model"]
    let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        try await Task.sleep(for: .seconds(delay))
        return LLMResponse(model: "stub-model", content: [.text("late answer")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        throw StubStreamError()
    }
}

/// 抛错桩：消息含 "boom" 时 LLM 请求失败（用于 error 字段测试）
final class ThrowingStubLLM: LLMProvider, @unchecked Sendable {
    struct BoomError: Error, Sendable {}

    let id = "throwing"
    let supportedModels = ["stub-model"]

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        for message in request.messages where message.role == .user {
            for block in message.content {
                if case let .text(text) = block, text.contains("boom") {
                    throw BoomError()
                }
            }
        }
        return LLMResponse(model: "stub-model", content: [.text("ok")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        throw StubStreamError()
    }
}

// MARK: - 测试辅助

private func testConfig() -> WebUIApp.Config {
    WebUIApp.Config(llm: StubLLM(), toolFactory: { [] }, model: "stub-model", maxSteps: 4, chatTimeout: 30)
}

private func makeServer(app: WebUIApp, maxBodyBytes: Int = 1_048_576) -> MiniHTTPServer {
    MiniHTTPServer(port: 0, maxBodyBytes: maxBodyBytes) { request in
        await app.handle(request)
    }
}

/// 启动临时服务器执行用例，结束后确保 stop（defer 在 async 上下文合法）
private func withServer<T: Sendable>(
    app: WebUIApp,
    maxBodyBytes: Int = 1_048_576,
    _ body: (_ base: String) async throws -> T
) async throws -> T {
    let server = makeServer(app: app, maxBodyBytes: maxBodyBytes)
    let port = try await server.start()
    do {
        let result = try await body("http://127.0.0.1:\(port)")
        await server.stop()
        return result
    } catch {
        await server.stop()
        throw error
    }
}

private func jsonDict(_ data: Data) throws -> [String: Any] {
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw StubStreamError()
    }
    return dict
}

private func jsonArray(_ data: Data) throws -> [[String: Any]] {
    guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw StubStreamError()
    }
    return array
}

private func get(_ base: String, path: String) async throws -> (data: Data, status: Int) {
    let url = URL(string: base + path)
    guard let url else { throw StubStreamError() }
    let (data, response) = try await URLSession.shared.data(from: url)
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    return (data, status)
}

private func post(_ base: String, path: String, body: Data) async throws -> (data: Data, status: Int) {
    let url = URL(string: base + path)
    guard let url else { throw StubStreamError() }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    return (data, status)
}

// MARK: - 请求解析（纯函数）

struct HTTPMessageParseTests {}

extension HTTPMessageParseTests {
    @Test("parseHead：请求行/路径/query/头解析")
    func parseHeadBasic() throws {
        let head = "POST /api/chat?a=1&b=hello%20world HTTP/1.1\r\nHost: localhost\r\nContent-Length: 12\r\n"
        let request = try HTTPRequest.parseHead(head, bodyPrefix: Data())
        #expect(request.method == "POST")
        #expect(request.path == "/api/chat")
        #expect(request.query["a"] == "1")
        #expect(request.query["b"] == "hello world")
        #expect(request.header("content-length") == "12")
        #expect(request.header("CONTENT-LENGTH") == "12")
        #expect(request.contentLength == 12)
    }

    @Test("parseHead：无 Content-Length 时正文长度为 0")
    func parseHeadNoBody() throws {
        let head = "GET /healthz HTTP/1.1\r\nHost: x\r\n"
        let request = try HTTPRequest.parseHead(head, bodyPrefix: Data())
        #expect(request.contentLength == 0)
        #expect(request.body.isEmpty)
    }

    @Test("parseHead：空行后的数据作为正文前缀")
    func parseHeadBodyPrefix() throws {
        let head = "POST /api/chat HTTP/1.1\r\nContent-Length: 5\r\n"
        let request = try HTTPRequest.parseHead(head, bodyPrefix: Data("hello".utf8))
        #expect(request.body == Data("hello".utf8))
    }

    @Test("parseHead：请求行不合法抛错")
    func parseHeadBadLine() {
        for bad in ["", "POST /no-version", "POST //path HTTP/2.x", "GET", "GET /path extra HTTP/1.1 extra"] {
            #expect(throws: HTTPError.self) {
                _ = try HTTPRequest.parseHead(bad + "\r\n", bodyPrefix: Data())
            }
        }
    }

    @Test("parseHead：头行不合法抛错")
    func parseHeadBadHeader() {
        let head = "GET / HTTP/1.1\r\nno-colon-line\r\n"
        #expect(throws: HTTPError.self) {
            _ = try HTTPRequest.parseHead(head, bodyPrefix: Data())
        }
    }

    @Test("parseHead：单字段 query 与编码值")
    func parseHeadQueryEdge() throws {
        let head = "GET /x?only&b=%2F%2Fa%3D1 HTTP/1.1\r\n"
        let request = try HTTPRequest.parseHead(head, bodyPrefix: Data())
        #expect(request.query["only"]?.isEmpty == true)
        #expect(request.query["b"] == "//a=1")
    }
}

// MARK: - 响应渲染（纯函数）

struct HTTPMessageRenderTests {}

extension HTTPMessageRenderTests {
    @Test("render：状态行/头/正文完整且 CRLF 分隔")
    func renderBasic() {
        let response = HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("hi".utf8))
        let rendered = String(data: response.render(), encoding: .utf8) ?? ""
        #expect(rendered.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(rendered.contains("content-type: text/plain\r\n"))
        #expect(rendered.contains("content-length: 2\r\n"))
        #expect(rendered.contains("connection: close\r\n"))
        #expect(rendered.hasSuffix("\r\n\r\nhi"))
    }

    @Test("render：状态码短语映射")
    func reasonPhrases() {
        #expect(HTTPResponse.reasonPhrase(for: 404) == "Not Found")
        #expect(HTTPResponse.reasonPhrase(for: 413) == "Payload Too Large")
        #expect(HTTPResponse.reasonPhrase(for: 504) == "Unknown")
    }

    @Test("错误响应工厂：状态码与 error 字段")
    func errorFactories() {
        let notFound = HTTPResponse.notFound()
        #expect(notFound.status == 404)
        let badRequest = HTTPResponse.badRequest("x")
        #expect(badRequest.status == 400)
        let methodNotAllowed = HTTPResponse.methodNotAllowed("y")
        #expect(methodNotAllowed.status == 405)
        let tooLarge = HTTPResponse.tooLarge()
        #expect(tooLarge.status == 413)
        let body = String(data: badRequest.body, encoding: .utf8) ?? ""
        #expect(body.contains("\"x\""))
    }
}

// MARK: - 真实 socket 回环

struct ServerRoundTripTests {
    @Test("healthz 与首页")
    func healthzAndPage() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app) { base in
            let (healthData, healthStatus) = try await get(base, path: "/healthz")
            #expect(healthStatus == 200)
            #expect(healthData.contains(Data("ok".utf8)))

            let (pageData, pageStatus) = try await get(base, path: "/")
            #expect(pageStatus == 200)
            let page = String(data: pageData, encoding: .utf8) ?? ""
            #expect(page.contains("<!DOCTYPE html>"))
            #expect(page.contains("Harness"))
            #expect(page.contains("/api/chat"))
        }
    }

    @Test("对话：新建会话 + 同会话多轮上下文保持")
    func chatMultiTurn() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app) { base in
            let (firstData, firstStatus) = try await post(base, path: "/api/chat", body: Data(#"{"message":"first"}"#.utf8))
            #expect(firstStatus == 200)
            let first = try jsonDict(firstData)
            guard let sessionId = first["sessionId"] as? String else { throw StubStreamError() }
            guard let firstReply = first["reply"] as? String else { throw StubStreamError() }
            #expect(firstReply == "echo[1]:first#1")

            let secondBody = Data(#"{"sessionId":"\#(sessionId)","message":"second"}"#.utf8)
            let (secondData, _) = try await post(base, path: "/api/chat", body: secondBody)
            let second = try jsonDict(secondData)
            #expect(second["sessionId"] as? String == sessionId)
            guard let secondReply = second["reply"] as? String else { throw StubStreamError() }
            // 第二轮请求应携带 2 条 user 历史
            #expect(secondReply == "echo[2]:second#2")
        }
    }

    @Test("对话：不同会话互不串线")
    func chatIsolation() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app) { base in
            let (aData, _) = try await post(base, path: "/api/chat", body: Data(#"{"message":"A"}"#.utf8))
            let a = try jsonDict(aData)
            let (bData, _) = try await post(base, path: "/api/chat", body: Data(#"{"message":"B"}"#.utf8))
            let b = try jsonDict(bData)
            #expect(a["sessionId"] as? String != b["sessionId"] as? String)
            #expect(a["reply"] as? String == "echo[1]:A#1")
            #expect(b["reply"] as? String == "echo[1]:B#2")
        }
    }

    @Test("会话列表：按创建时间倒序 + 标题取首条消息")
    func sessionsList() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app) { base in
            _ = try await post(base, path: "/api/chat", body: Data(#"{"message":"alpha"}"#.utf8))
            try? await Task.sleep(for: .milliseconds(20))
            let (secondData, _) = try await post(base, path: "/api/chat", body: Data(#"{"message":"beta"}"#.utf8))
            let second = try jsonDict(secondData)
            guard let secondId = second["sessionId"] as? String else { throw StubStreamError() }

            let (listData, listStatus) = try await get(base, path: "/api/sessions")
            #expect(listStatus == 200)
            let list = try jsonArray(listData)
            #expect(list.count == 2)
            #expect(list[0]["id"] as? String == secondId)
            #expect(list[0]["title"] as? String == "beta")
            #expect(list[1]["title"] as? String == "alpha")
        }
    }

    @Test("404 与 405")
    func notFoundAndMethodNotAllowed() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app) { base in
            let (nfData, nfStatus) = try await get(base, path: "/nope")
            #expect(nfStatus == 404)
            #expect(nfData.contains(Data("unknown route".utf8)))

            let (_, msStatus) = try await post(base, path: "/healthz", body: Data())
            #expect(msStatus == 405)

            let (_, ms2Status) = try await get(base, path: "/api/chat")
            #expect(ms2Status == 405)
        }
    }

    @Test("请求体超限返回 413")
    func oversizedBody() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app, maxBodyBytes: 1024) { base in
            let big = Data(repeating: 0x41, count: 2048)
            let (_, status) = try await post(base, path: "/api/chat", body: big)
            #expect(status == 413)
        }
    }

    @Test("坏 JSON 返回 400")
    func badJSON() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app) { base in
            let (data, status) = try await post(base, path: "/api/chat", body: Data("{not json".utf8))
            #expect(status == 400)
            #expect(data.contains(Data("invalid JSON".utf8)))
        }
    }

    @Test("空消息返回 400")
    func emptyMessage() async throws {
        let app = WebUIApp(config: testConfig())
        try await withServer(app: app) { base in
            let (data, status) = try await post(base, path: "/api/chat", body: Data(#"{"message":"   "}"#.utf8))
            #expect(status == 400)
            _ = data
        }
    }

    @Test("无效监听地址抛 invalidHost")
    func invalidHost() async throws {
        let server = MiniHTTPServer(host: "999.999.999.999", port: 0) { _ in .notFound() }
        do {
            _ = try await server.start()
            Issue.record("无效地址应抛错")
        } catch is SocketError {
            // 预期：invalidHost
        }
    }

    @Test("超大请求头返回 400")
    func oversizedHead() async throws {
        // maxHeadBytes=32：任何正常 GET 的请求头（含 Host 等）都超限
        let server = MiniHTTPServer(port: 0, maxHeadBytes: 32) { _ in HTTPResponse.notFound() }
        let port = try await server.start()
        do {
            let (data, status) = try await get("http://127.0.0.1:\(port)", path: "/")
            #expect(status == 400)
            #expect(data.contains(Data("request head too large".utf8)))
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    @Test("对话超时返回 504")
    func chatTimeout504() async throws {
        let config = WebUIApp.Config(llm: SlowStubLLM(delay: 2), toolFactory: { [] }, model: "stub-model", chatTimeout: 0.5)
        let app = WebUIApp(config: config)
        try await withServer(app: app) { base in
            let (data, status) = try await post(base, path: "/api/chat", body: Data(#"{"message":"slow"}"#.utf8))
            #expect(status == 504)
            #expect(data.contains(Data("chat timed out".utf8)))
        }
    }

    @Test("LLM 错误返回 error 字段")
    func llmErrorField() async throws {
        let config = WebUIApp.Config(llm: ThrowingStubLLM(), toolFactory: { [] }, model: "stub-model")
        let app = WebUIApp(config: config)
        try await withServer(app: app) { base in
            let (data, status) = try await post(base, path: "/api/chat", body: Data(#"{"message":"boom"}"#.utf8))
            #expect(status == 200)
            let dict = try jsonDict(data)
            #expect((dict["error"] as? String)?.isEmpty == false)
            #expect((dict["reply"] as? String).map(\.isEmpty) == true)
        }
    }

    @Test("stop 后连接被拒绝")
    func stopClosesServer() async throws {
        let app = WebUIApp(config: testConfig())
        let server = makeServer(app: app)
        let port = try await server.start()
        await server.stop()

        let url = URL(string: "http://127.0.0.1:\(port)/healthz")
        guard let url else { throw StubStreamError() }
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("stop 后不应再接受连接")
        } catch {
            // 预期：连接失败
        }
    }
}
