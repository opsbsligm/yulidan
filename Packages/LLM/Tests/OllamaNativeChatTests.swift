import Foundation
@testable import LLM
import XCTest

// MARK: - Ollama 原生 API 客户端（/api/chat）— 零真实网络（复用 LLMHTTPStubTests 的 StubURLProtocol）

//
// 背景（2026-08-27 实机实证）：OpenAI 兼容端点不受理 options 字段（num_ctx 被忽略，runner 仍 -c 4096），
// 仅原生 /api/chat 的 options.num_ctx 能真实控制本地上下文窗口。本文件锁死原生请求/响应 wire 契约。

let okCompletionNative = """
{"model":"qwen3:4b","message":{"role":"assistant","content":"hi"},"done_reason":"stop","done":true,"prompt_eval_count":10,"eval_count":5}
"""

let okCompletionNativeTool = """
{"model":"qwen3:4b","message":{"role":"assistant","content":"好","thinking":"思考过程",
"tool_calls":[{"function":{"name":"get_weather","arguments":{"city":"北京"}}}]},"done_reason":"tool_calls","done":true,"prompt_eval_count":10,"eval_count":5}
"""

/// 3 行 NDJSON：text 增量 / thinking+text / 终态 tool_calls+done_reason+eval counts
let okNDJSONNative = """
{"message":{"role":"assistant","content":"你"},"done":false}
{"message":{"role":"assistant","thinking":"让我想想","content":"好"},"done":false}
{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"get_weather","arguments":{"city":"北京"}}}]},"done_reason":"stop","done":true,"prompt_eval_count":10,"eval_count":5}
"""

final class OllamaNativeChatTests: XCTestCase {
    private let base = URL(string: "http://stub.local")!

    private func client(_ session: URLSession = makeStubSession()) -> OllamaNativeChat {
        OllamaNativeChat(baseURL: base, session: session)
    }

    private func bodyDict() throws -> [String: Any] {
        try (JSONSerialization.jsonObject(with: StubURLProtocol.lastBody!) as? [String: Any]) ?? [:]
    }

    /// ① 请求 wire：/api/chat + options{num_ctx,num_predict} + think + stream:false
    func testRequestWireOptionsThinkStreamFalse() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletionNative, contentType: "application/json") }
        _ = try await client().complete(model: "qwen3:4b",
                                        messages: [Message(role: .user, content: [.text("hi")])],
                                        maxTokens: 4096, numCtx: 32768, think: "high")
        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(try XCTUnwrap(req.url?.path), "/api/chat", "原生路径必须打 /api/chat 而非 /v1/chat/completions")
        XCTAssertNil(req.value(forHTTPHeaderField: "Accept"), "非流式不应带 NDJSON Accept")
        let body = try bodyDict()
        XCTAssertEqual(body["model"] as? String, "qwen3:4b")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["think"] as? String, "high", "思考等级走原生顶层 think 字段")
        let opts = body["options"] as? [String: Any]
        XCTAssertEqual(opts?["num_ctx"] as? Int, 32768)
        XCTAssertEqual(opts?["num_predict"] as? Int, 4096)
    }

    /// ② 无 maxTokens/numCtx/think → body 不含 options / think（不下发死字段）
    func testNoOptionsAndThinkByDefault() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletionNative, contentType: "application/json") }
        _ = try await client().complete(model: "qwen3:4b",
                                        messages: [Message(role: .user, content: [.text("hi")])])
        let body = try bodyDict()
        XCTAssertNil(body["options"], "未设置 maxTokens/numCtx 时不应下发 options 字段")
        XCTAssertNil(body["think"], "未设置 think 时不应下发 think 字段")
    }

    /// ③ 工具历史 wire：assistant tool_calls arguments 为 JSON 对象；tool 结果消息带 tool_name（官方文档格式）
    func testToolHistoryWire() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletionNative, contentType: "application/json") }
        let history: [Message] = [
            Message(role: .user, content: [.text("北京天气？")]),
            Message(role: .assistant, content: [.toolCall(ToolCallBlock(id: "call-0", name: "get_weather",
                                                                        arguments: #"{"city":"北京"}"#))]),
            Message(role: .tool, content: [.toolResult(ToolResultBlock(toolCallId: "call-0",
                                                                       content: [.text("晴 25°C")], isError: false))]),
        ]
        _ = try await client().complete(model: "qwen3:4b", messages: history)
        let body = try bodyDict()
        let msgs = body["messages"] as? [[String: Any]]
        XCTAssertEqual(msgs?.count, 3)
        let assistantMsg = msgs?[1]
        XCTAssertEqual(assistantMsg?["role"] as? String, "assistant")
        XCTAssertNil(assistantMsg?["content"], "纯 tool_calls 的 assistant 消息 content 应为空")
        let calls = (assistantMsg?["tool_calls"] as? [[String: Any]]) ?? []
        let fn = calls.first?["function"] as? [String: Any]
        XCTAssertEqual(fn?["name"] as? String, "get_weather")
        let args = fn?["arguments"] as? [String: Any]
        XCTAssertEqual(args?["city"] as? String, "北京", "官方协议：arguments 是 JSON 对象，不是 OpenAI 的字符串")
        let toolMsg = msgs?[2]
        XCTAssertEqual(toolMsg?["role"] as? String, "tool")
        XCTAssertEqual(toolMsg?["content"] as? String, "晴 25°C")
        XCTAssertEqual(toolMsg?["tool_name"] as? String, "get_weather", "tool 结果消息须带 tool_name（官方文档示例）")
    }

    /// ④ 非流式解析：content/thinking→reasoning/toolCalls/usage/finishReason
    func testNonStreamParse() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletionNativeTool, contentType: "application/json") }
        let r = try await client().complete(model: "qwen3:4b",
                                            messages: [Message(role: .user, content: [.text("hi")])])
        XCTAssertEqual(r.content, "好")
        XCTAssertEqual(r.reasoning, "思考过程", "message.thinking 应映射为 reasoning")
        XCTAssertEqual(r.toolCalls.count, 1)
        XCTAssertEqual(r.toolCalls[0].name, "get_weather")
        let args = try JSONSerialization.jsonObject(with: Data(r.toolCalls[0].arguments.utf8)) as? [String: Any]
        XCTAssertEqual(args?["city"] as? String, "北京", "arguments 按 JSON 解析比较")
        XCTAssertEqual(r.usage?.promptTokens, 10)
        XCTAssertEqual(r.usage?.completionTokens, 5)
        XCTAssertEqual(r.usage?.totalTokens, 15)
        XCTAssertEqual(r.finishReason, .toolCalls)
    }

    /// ⑤ done_reason → FinishReason 映射（官方取值：stop/length/context_overflow/prompt_too_long/abort/error_*）
    func testMapDoneReason() {
        XCTAssertEqual(OllamaNativeChat.mapDoneReason("stop"), .stop)
        XCTAssertEqual(OllamaNativeChat.mapDoneReason("load"), .stop)
        XCTAssertEqual(OllamaNativeChat.mapDoneReason("length"), .length)
        XCTAssertEqual(OllamaNativeChat.mapDoneReason("context_overflow"), .length)
        XCTAssertEqual(OllamaNativeChat.mapDoneReason("prompt_too_long"), .length)
        XCTAssertEqual(OllamaNativeChat.mapDoneReason("tool_calls"), .toolCalls)
        XCTAssertEqual(OllamaNativeChat.mapDoneReason(nil), .stop, "未知/缺失回落 .stop")
        XCTAssertEqual(OllamaNativeChat.mapDoneReason("error_unknown"), .stop)
    }

    /// ⑥ NDJSON 流事件序列：.text → .reasoning → .text → .done（含 usage/toolCalls）
    func testNDJSONStreamEventSequence() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okNDJSONNative, contentType: "application/x-ndjson") }
        var events: [OpenAIStreamEvent] = []
        for try await e in client().streamEvents(model: "qwen3:4b",
                                                 messages: [Message(role: .user, content: [.text("hi")])]) {
            events.append(e)
        }
        XCTAssertEqual(try XCTUnwrap(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept")),
                       "application/x-ndjson", "流式应声明 NDJSON Accept")
        XCTAssertEqual(events.count, 4)
        guard case let .text(t1)? = events.first else { return XCTFail("首事件应为 text，实际 \(events.first!)") }
        XCTAssertEqual(t1, "你")
        guard case let .reasoning(r1)? = events.dropFirst().first else { return XCTFail("第二事件应为 reasoning") }
        XCTAssertEqual(r1, "让我想想")
        guard case let .text(t2)? = events.dropFirst(2).first else { return XCTFail("第三事件应为 text") }
        XCTAssertEqual(t2, "好")
        guard case let .done(finish, usage, calls)? = events.last else { return XCTFail("末事件应为 done") }
        XCTAssertEqual(finish, .stop)
        XCTAssertEqual(usage?.totalTokens, 15)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "get_weather")
    }

    /// ⑦ 非 2xx → httpError
    func testHTTP500ThrowsHttpError() async {
        StubURLProtocol.handler = { _ in .init(status: 500, body: "model error", contentType: "application/json") }
        do {
            _ = try await client().complete(model: "m", messages: [Message(role: .user, content: [.text("hi")])])
            XCTFail("应当抛出 httpError")
        } catch let e as LLMError {
            guard case let .httpError(status, body) = e else {
                return XCTFail("预期 httpError，实际 \(e)")
            }
            XCTAssertEqual(status, 500)
            XCTAssertEqual(body, "model error")
        } catch {
            XCTFail("意外错误 \(error)")
        }
    }
}
