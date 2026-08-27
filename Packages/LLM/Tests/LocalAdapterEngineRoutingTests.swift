import Foundation
@testable import LLM
import XCTest

// MARK: - LocalAdapter 引擎路由（Ollama 原生 /api/chat vs OpenAI 兼容 /v1/chat/completions）

//
// 探测契约（GET {nativeBase}/api/tags）：200 且 JSON 含 "models" key → ollamaNative；
// 404 / 599 / 探测失败 → openAICompat（保持旧行为）。引擎按实例缓存。

final class LocalAdapterEngineRoutingTests: XCTestCase {
    private let base = URL(string: "http://stub.local/v1")!

    private func adapter(_ session: URLSession = makeStubSession()) -> LocalAdapter {
        LocalAdapter(apiKey: "k", baseURL: base, session: session, profile: .local)
    }

    /// 路由桩：/api/tags 按 tagsStatus 应答；/api/chat 回原生 200；/v1/chat/completions 回兼容 200
    private func routeHandler(tagsStatus: Int, tagsBody: String = #"{"models":[]}"#) -> (URLRequest) -> StubURLProtocol.Canned {
        { req in
            switch req.url?.path {
            case "/api/tags":
                .init(status: tagsStatus, body: tagsBody, contentType: "application/json")
            case "/api/chat":
                .init(status: 200, body: okCompletionNative, contentType: "application/json")
            case "/v1/chat/completions":
                .init(status: 200, body: okCompletion, contentType: "application/json")
            default:
                .init(status: 599, body: "unexpected \(req.url!.path)", contentType: "application/json")
            }
        }
    }

    private func lastBodyDict() throws -> [String: Any] {
        // 用 stub 捕获的 lastBody（httpBody 可能被 URLSession 转为 httpBodyStream）
        try (JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: Any]) ?? [:]
    }

    /// ① 探测命中 Ollama → 原生路径 /api/chat，options.num_ctx 真实下发
    func testOllamaDetectedRoutesNativeWithNumCtx() async throws {
        StubURLProtocol.handler = routeHandler(tagsStatus: 200)
        _ = try await adapter().request(LLMRequest(model: "qwen3:4b",
                                                   messages: [Message(role: .user, content: [.text("hi")])],
                                                   numCtx: 131_072))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/api/chat")
        let body = try lastBodyDict()
        XCTAssertEqual((body["options"] as? [String: Any])?["num_ctx"] as? Int, 131_072,
                       "Ollama 原生路径必须真实下发 options.num_ctx")
    }

    /// ② 非 Ollama（/api/tags 404）→ 兼容路径，且不下发 options（vLLM/LM Studio 不支持）
    func testNonOllamaFallsBackToCompatWithoutOptions() async throws {
        StubURLProtocol.handler = routeHandler(tagsStatus: 404)
        _ = try await adapter().request(LLMRequest(model: "m",
                                                   messages: [Message(role: .user, content: [.text("hi")])],
                                                   numCtx: 131_072))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/chat/completions")
        let body = try lastBodyDict()
        XCTAssertNil(body["options"], "OpenAI 兼容路径不应下发 options 字段")
    }

    /// ③ 探测失败（/api/tags 599）→ 兼容路径兜底
    func testProbeFailureFallsBackToCompat() async throws {
        StubURLProtocol.handler = routeHandler(tagsStatus: 599)
        _ = try await adapter().request(LLMRequest(model: "m",
                                                   messages: [Message(role: .user, content: [.text("hi")])],
                                                   numCtx: 131_072))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/chat/completions")
    }

    /// ④ 探测命中但响应体无 models key → 兼容路径（仅状态码不够，须含 models）
    func testTagsWithoutModelsKeyFallsBackToCompat() async throws {
        StubURLProtocol.handler = routeHandler(tagsStatus: 200, tagsBody: #"{"foo":1}"#)
        _ = try await adapter().request(LLMRequest(model: "m",
                                                   messages: [Message(role: .user, content: [.text("hi")])]))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/chat/completions")
    }

    /// ⑤ 流式路由：原生 NDJSON → StreamChunk 序列以 message_complete 收尾（AgentLoop 契约一致）
    func testStreamRoutesNativeAndEmitsMessageComplete() async throws {
        StubURLProtocol.handler = { req in
            if req.url?.path == "/api/tags" {
                return .init(status: 200, body: #"{"models":[]}"#, contentType: "application/json")
            }
            if req.url?.path == "/api/chat" {
                return .init(status: 200, body: okNDJSONNative, contentType: "application/x-ndjson")
            }
            return .init(status: 599, body: "unexpected \(req.url!.path)", contentType: "application/json")
        }
        var chunkTypes: [String] = []
        let streamReq = LLMRequest(model: "qwen3:4b", messages: [Message(role: .user, content: [.text("hi")])])
        for try await chunk in try await adapter().stream(streamReq) {
            chunkTypes.append(chunk.type)
        }
        XCTAssertEqual(try XCTUnwrap(StubURLProtocol.lastRequest?.url?.path), "/api/chat", "流式也必须走原生路径")
        XCTAssertTrue(chunkTypes.contains("text"), "应有 text 增量 chunk")
        XCTAssertTrue(chunkTypes.last == "message_complete", "终态 chunk 应为 message_complete")
    }
}
