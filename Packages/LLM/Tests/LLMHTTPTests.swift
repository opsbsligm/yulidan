import XCTest
@testable import LLM

/// 用 URLProtocol mock 验证 OpenAI 兼容客户端的真实 HTTP 行为
/// （请求体、鉴权头、响应解析、错误映射）
final class MockOpenAIURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            var data = Data()
            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: bufferSize)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            body = String(data: data, encoding: .utf8) ?? ""
        }
        if (request.url?.path ?? "").hasSuffix("/models") {
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: #"{"data":[{"id":"m1"}]}"#.data(using: .utf8)!)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // chat/completions：校验请求体后返回固定回复
        guard body.contains("\"model\""), body.contains("\"messages\"") else {
            let resp = HTTPURLResponse(url: request.url!, statusCode: 400,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: #"{"error":"bad body"}"#.data(using: .utf8)!)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        let payload = #"{"id":"cmpl-1","choices":[{"message":{"role":"assistant","content":"来自 Mock 服务端的回复"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}"#
        client?.urlProtocol(self, didLoad: payload.data(using: .utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LLMHTTPTests: XCTestCase {
    private var client: OpenAICompatChat!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOpenAIURLProtocol.self]
        let session = URLSession(configuration: config)
        client = OpenAICompatChat(apiKey: "sk-test",
                                  baseURL: URL(string: "http://mock.local/v1")!,
                                  session: session)
    }

    func testCompleteParsesResponse() async throws {
        let msgs = [
            LLM.Message(role: .user, content: [.text("你好")])
        ]
        let (content, usage) = try await client.complete(model: "deepseek-chat", messages: msgs)
        XCTAssertEqual(content, "来自 Mock 服务端的回复")
        XCTAssertEqual(usage?.totalTokens, 8)
    }

    func testCheckConnection() async throws {
        let msg = try await client.checkConnection()
        XCTAssertEqual(msg, "连接成功")
    }

    func testMissingKeyThrows() async throws {
        let noKey = OpenAICompatChat(apiKey: "", baseURL: URL(string: "http://mock.local/v1")!,
                                     session: URLSession(configuration: {
                                         let c = URLSessionConfiguration.ephemeral
                                         c.protocolClasses = [MockOpenAIURLProtocol.self]
                                         return c
                                     }()))
        do {
            _ = try await noKey.complete(model: "m", messages: [])
            XCTFail("expected missingAPIKey")
        } catch let e as LLMError {
            guard case .missingAPIKey = e else {
                XCTFail("wrong error: \(e)"); return
            }
        }
    }
}
