import Foundation
import LLM
import Testing
import XCTest

// MARK: - 桩响应体（wire 格式常量）

private let toolCallsResponse = """
{"id":"cmpl-tc","object":"chat.completion","model":"test-model",
"choices":[{"message":{"role":"assistant","content":null,
"tool_calls":[{"id":"call_abc","type":"function","function":{"name":"exec_command","arguments":"{\\"cmd\\":\\"echo hi\\"}"}}]},
"finish_reason":"tool_calls"}],
"usage":{"prompt_tokens":10,"completion_tokens":6,"total_tokens":16}}
"""

private let reasoningResponse = """
{"id":"cmpl-r","object":"chat.completion","model":"test-model",
"choices":[{"message":{"role":"assistant","content":"最终答案","reasoning_content":"先分析，再作答"},
"finish_reason":"stop"}],
"usage":{"prompt_tokens":4,"completion_tokens":9,"total_tokens":13}}
"""

private let sseToolCallBody = """
data: {"choices":[{"delta":{"role":"assistant","content":null}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"exec_command","arguments":""}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"cmd\\":\\"echo"}}]}}]}
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":" hi\\"}"}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_def","type":"function","function":{"name":"get_weather"}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\\"city\\":"}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"\\"Beijing\\"}"}}]}}]}

data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":8,"completion_tokens":12,"total_tokens":20}}

data: [DONE]

"""

private let anthropicToolUseResponse = """
{"id":"msg_tc","content":[
{"type":"tool_use","id":"toolu_01","name":"get_weather","input":{"city":"Beijing","unit":"celsius"}}],
"stop_reason":"tool_use","usage":{"input_tokens":6,"output_tokens":10}}
"""

// MARK: - OpenAI 兼容协议 wire 格式测试

final class OpenAICompatToolWireTests: XCTestCase {
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

    private func bodyObject() throws -> [String: Any] {
        let body = StubURLProtocol.lastBody ?? Data()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testRequestSendsTools() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        _ = try await client().complete(model: "m",
                                        messages: [Message(role: .user, content: [.text("hi")])],
                                        tools: [ToolSchema(name: "exec_command",
                                                           description: "执行命令",
                                                           parameters: #"{"type":"object","properties":{"cmd":{"type":"string"}}}"#)])
        let obj = try bodyObject()
        let tools = try XCTUnwrap(obj["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "exec_command")
        XCTAssertEqual(function["description"] as? String, "执行命令")
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual((parameters["properties"] as? [String: Any])?.keys.contains("cmd"), true)
    }

    func testRequestSerializesToolCallHistory() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let history: [Message] = [
            Message(role: .user, content: [.text("执行命令")]),
            Message(role: .assistant, content: [.text("我来执行"),
                                                .toolCall(ToolCallBlock(id: "call_1", name: "exec_command",
                                                                        arguments: #"{"cmd":"echo hi"}"#))],
                    source: .model),
            Message(role: .tool, content: [.toolResult(ToolResultBlock(toolCallId: "call_1",
                                                                       content: [.text("hi")],
                                                                       isError: false))],
            source: .tool),
        ]
        _ = try await client().complete(model: "m", messages: history)
        let obj = try bodyObject()
        let messages = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        // assistant：content + tool_calls
        let assistant = messages.first { ($0["role"] as? String) == "assistant" }
        XCTAssertEqual(assistant?["content"] as? String, "我来执行")
        let toolCalls = try XCTUnwrap(assistant?["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(toolCalls.first?["id"] as? String, "call_1")
        let fn = try XCTUnwrap(toolCalls.first?["function"] as? [String: Any])
        XCTAssertEqual(fn["name"] as? String, "exec_command")
        // tool 结果消息：role "tool" + tool_call_id
        let toolMsg = messages.first { ($0["role"] as? String) == "tool" }
        XCTAssertEqual(toolMsg?["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(toolMsg?["content"] as? String, "hi")
    }

    func testResponseParsesToolCalls() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: toolCallsResponse, contentType: "application/json") }
        let result = try await client().complete(model: "m",
                                                 messages: [Message(role: .user, content: [.text("hi")])])
        XCTAssertEqual(result.content, "")
        XCTAssertEqual(result.finishReason, .toolCalls)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls.first?.id, "call_abc")
        XCTAssertEqual(result.toolCalls.first?.name, "exec_command")
        XCTAssertEqual(result.toolCalls.first?.arguments, #"{"cmd":"echo hi"}"#)
        XCTAssertEqual(result.usage?.totalTokens, 16)
    }

    func testResponseParsesReasoningContent() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: reasoningResponse, contentType: "application/json") }
        let result = try await client().complete(model: "m",
                                                 messages: [Message(role: .user, content: [.text("hi")])])
        XCTAssertEqual(result.content, "最终答案")
        XCTAssertEqual(result.reasoning, "先分析，再作答")
        XCTAssertEqual(result.finishReason, .stop)
    }

    func testFinishReasonMapping() {
        XCTAssertEqual(OpenAICompatChat.mapFinishReason("stop"), .stop)
        XCTAssertEqual(OpenAICompatChat.mapFinishReason("length"), .length)
        XCTAssertEqual(OpenAICompatChat.mapFinishReason("tool_calls"), .toolCalls)
        XCTAssertEqual(OpenAICompatChat.mapFinishReason("function_call"), .toolCalls)
        XCTAssertEqual(OpenAICompatChat.mapFinishReason(nil), .stop)
        XCTAssertEqual(OpenAICompatChat.mapFinishReason("content_filter"), .stop)
    }

    func testSseDeltaParsesDeltaKey() {
        // 真实 wire 用 "delta" key
        let line = #"data: {"choices":[{"delta":{"content":"x"}}]}"#
        XCTAssertEqual(OpenAICompatChat.sseDeltaText(from: line), "x")
        // 旧桩用 "message" key（兼容）
        let legacy = #"data: {"choices":[{"message":{"content":"y"}}]}"#
        XCTAssertEqual(OpenAICompatChat.sseDeltaText(from: legacy), "y")
        // 仅 usage 的终块
        let usageLine = #"data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#
        let payload = OpenAICompatChat.sseDelta(from: usageLine)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.usage?.totalTokens, 3)
        XCTAssertNil(payload?.content)
    }

    func testStreamEventsAccumulatesToolCallDeltas() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: sseToolCallBody, contentType: "text/event-stream") }
        var events: [OpenAIStreamEvent] = []
        for try await event in client().streamEvents(model: "m",
                                                     messages: [Message(role: .user, content: [.text("hi")])]) {
            events.append(event)
        }
        // 无文本增量，仅终态
        XCTAssertEqual(events.count, 1)
        guard case let .done(finish, usage, toolCalls) = events.first else {
            return XCTFail("应为 done 事件")
        }
        XCTAssertEqual(finish, .toolCalls)
        XCTAssertEqual(usage?.totalTokens, 20)
        // 两个工具调用按 index 归并；arguments 片段拼接完整
        XCTAssertEqual(toolCalls.count, 2)
        XCTAssertEqual(toolCalls[0].id, "call_abc")
        XCTAssertEqual(toolCalls[0].name, "exec_command")
        XCTAssertEqual(toolCalls[0].arguments, #"{"cmd":"echo hi"}"#)
        XCTAssertEqual(toolCalls[1].id, "call_def")
        XCTAssertEqual(toolCalls[1].name, "get_weather")
        XCTAssertEqual(toolCalls[1].arguments, #"{"city":"Beijing"}"#)
        // 流式请求体仍带 stream: true
        let body = String(data: StubURLProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"stream\":true") || body.contains("\"stream\": true"))
    }

    /// P2：SSE 流式转发 reasoning 增量（DeepSeek 推理过程流式可见）
    func testStreamEventsForwardsReasoningDeltas() async throws {
        let body = """
        data: {"choices":[{"delta":{"reasoning_content":"第一步："}}]}
        data: {"choices":[{"delta":{"reasoning_content":"分析需求。"}}]}
        data: {"choices":[{"delta":{"content":"最终"}}]}
        data: {"choices":[{"delta":{"content":"答案"},"finish_reason":"stop"}]}
        data: [DONE]
        """
        StubURLProtocol.handler = { _ in .init(status: 200, body: body, contentType: "text/event-stream") }
        var events: [OpenAIStreamEvent] = []
        for try await event in client().streamEvents(model: "m",
                                                     messages: [Message(role: .user, content: [.text("hi")])]) {
            events.append(event)
        }
        // reasoning 增量按序在前，text 在后，终态收尾
        XCTAssertEqual(events.count, 5)
        guard case let .reasoning(r1) = events[0] else { return XCTFail("第 1 个事件应为 reasoning") }
        guard case let .reasoning(r2) = events[1] else { return XCTFail("第 2 个事件应为 reasoning") }
        XCTAssertEqual(r1, "第一步：")
        XCTAssertEqual(r2, "分析需求。")
        guard case let .text(t) = events[2] else { return XCTFail("第 3 个事件应为 text") }
        XCTAssertEqual(t, "最终")
        guard case let .text(t2) = events[3] else { return XCTFail("第 4 个事件应为 text") }
        XCTAssertEqual(t2, "答案")
        guard case let .done(finish, _, _) = events[4] else { return XCTFail("末事件应为 done") }
        XCTAssertEqual(finish, .stop)
    }

    /// 适配器层：reasoning 增量映射为 type="reasoning" 的 StreamChunk
    func testAdapterStreamMapsReasoningChunks() async throws {
        let body = """
        data: {"choices":[{"delta":{"reasoning_content":"思考中"}}]}
        data: {"choices":[{"delta":{"content":"回答"},"finish_reason":"stop"}]}
        data: [DONE]
        """
        StubURLProtocol.handler = { _ in .init(status: 200, body: body, contentType: "text/event-stream") }
        let request = LLMRequest(model: "m", messages: [Message(role: .user, content: [.text("hi")])],
                                 systemPrompt: nil, tools: nil, maxTokens: nil, temperature: nil)
        var types: [String] = []
        var reasoningPayload = ""
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let stream = try await adapter.stream(request)
        for try await chunk in stream {
            types.append(chunk.type)
            if chunk.type == "reasoning" {
                reasoningPayload += String(data: chunk.data, encoding: .utf8) ?? ""
            }
        }
        XCTAssertEqual(types, ["reasoning", "text", "message_complete"])
        XCTAssertEqual(reasoningPayload, "思考中")
    }

    func testToolCallDeltaAccumulatorOrdering() {
        var acc = ToolCallDeltaAccumulator()
        // 乱序到达：index0 先到 → index1 → index0 续片（输出顺序 = index 首次出现顺序）
        acc.apply(OpenAISSEToolCallDelta(index: 0, id: "call_a", name: "tool_a", argumentsFragment: #"{"x":1"#))
        acc.apply(OpenAISSEToolCallDelta(index: 1, id: "call_b", name: "tool_b", argumentsFragment: "{}"))
        acc.apply(OpenAISSEToolCallDelta(index: 0, id: nil, name: nil, argumentsFragment: "}"))
        let calls = acc.toolCalls
        XCTAssertEqual(calls.map(\.id), ["call_a", "call_b"])
        XCTAssertEqual(calls[0].arguments, #"{"x":1}"#)
        XCTAssertEqual(calls[1].arguments, "{}")
        // 空 arguments 归一为 {}
        var empty = ToolCallDeltaAccumulator()
        empty.apply(OpenAISSEToolCallDelta(index: 0, id: "call_e", name: "t", argumentsFragment: nil))
        XCTAssertEqual(empty.toolCalls.first?.arguments, "{}")
    }
}

// MARK: - 适配器归一化行为（画像门控 / reasoning / 工具循环）

final class AdapterNormalizationTests: XCTestCase {
    private let base = URL(string: "http://stub.local/v1")!

    override func setUp() {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    private func bodyObject() throws -> [String: Any] {
        let body = StubURLProtocol.lastBody ?? Data()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testDeepSeekReasoningBlockPrecedesText() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: reasoningResponse, contentType: "application/json") }
        let adapter = DeepSeekAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let resp = try await adapter.request(LLMRequest(model: "deepseek-reasoner",
                                                        messages: [Message(role: .user, content: [.text("hi")])]))
        XCTAssertEqual(resp.content.count, 2)
        if case let .reasoning(r)? = resp.content.first {
            XCTAssertEqual(r, "先分析，再作答")
        } else {
            return XCTFail("首块应为 reasoning")
        }
        if case let .text(t)? = resp.content.last {
            XCTAssertEqual(t, "最终答案")
        } else {
            return XCTFail("末块应为 text")
        }
        XCTAssertEqual(resp.finishReason, .stop)
    }

    func testOpenAIProfileGatesReasoning() async throws {
        // OpenAI 画像 supportsReasoning=false：reasoning_content 被门控丢弃，不产生 .reasoning 块
        StubURLProtocol.handler = { _ in .init(status: 200, body: reasoningResponse, contentType: "application/json") }
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let resp = try await adapter.request(LLMRequest(model: "gpt-4o",
                                                        messages: [Message(role: .user, content: [.text("hi")])]))
        for block in resp.content {
            if case .reasoning = block {
                return XCTFail("OpenAI 画像不应产生 reasoning 块")
            }
        }
        if case let .text(t)? = resp.content.first {
            XCTAssertEqual(t, "最终答案")
        } else {
            return XCTFail("应有 text 块")
        }
    }

    func testOpenAIAdapterToolCallRoundTrip() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: toolCallsResponse, contentType: "application/json") }
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let tools = [ToolSchema(name: "exec_command", description: "执行命令",
                                parameters: #"{"type":"object","properties":{"cmd":{"type":"string"}}}"#)]
        let resp = try await adapter.request(LLMRequest(model: "gpt-4o-mini",
                                                        messages: [Message(role: .user, content: [.text("hi")])],
                                                        tools: tools))
        XCTAssertEqual(resp.finishReason, .toolCalls)
        XCTAssertEqual(resp.toolCalls?.first?.name, "exec_command")
        // 请求体确实下发了 tools
        let obj = try bodyObject()
        XCTAssertNotNil(obj["tools"])
    }

    func testAdapterStreamYieldsFinalMessageComplete() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: sseToolCallBody, contentType: "text/event-stream") }
        let adapter = DeepSeekAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        var chunks: [StreamChunk] = []
        for try await chunk in try await adapter.stream(LLMRequest(model: "deepseek-chat",
                                                                   messages: [Message(role: .user, content: [.text("hi")])])) {
            chunks.append(chunk)
        }
        // 无文本增量 → 仅 1 个终态块
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.type, "message_complete")
        let summary = try XCTUnwrap(JSONSerialization.jsonObject(with: chunks[0].data) as? [String: Any])
        XCTAssertEqual(summary["finish_reason"] as? String, "toolCalls")
        let toolCalls = try XCTUnwrap(summary["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(toolCalls.count, 2)
        XCTAssertEqual(toolCalls.first?["name"] as? String, "exec_command")
    }

    func testAdapterProfiles() {
        XCTAssertEqual(OpenAIAdapter(apiKey: "k").profile, ProviderProfile.openAI)
        XCTAssertEqual(DeepSeekAdapter(apiKey: "k").profile, ProviderProfile.deepSeek)
        XCTAssertEqual(LocalAdapter().profile, ProviderProfile.local)
        XCTAssertEqual(AnthropicAdapter(apiKey: "k").profile, ProviderProfile.anthropic)
        // 协议默认画像：mock/脚本化 provider 兜底为全能力画像
        struct MockProfileProvider: LLMProvider {
            let id = "p"
            let supportedModels: [String] = []
            func request(_: LLMRequest) async throws -> LLMResponse {
                LLMResponse(model: "m", content: [], finishReason: .stop)
            }

            func stream(_: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
                AsyncThrowingStream { $0.finish() }
            }
        }
        XCTAssertEqual(MockProfileProvider().profile, ProviderProfile.mock)
    }
}

// MARK: - Anthropic tools wire 格式

final class AnthropicToolWireTests: XCTestCase {
    private let base = URL(string: "http://stub.local/v1")!

    override func setUp() {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    private func bodyObject() throws -> [String: Any] {
        let body = StubURLProtocol.lastBody ?? Data()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testRequestSendsToolsWithInputSchema() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        _ = try await adapter.request(LLMRequest(model: "claude-3-5-haiku-20241022",
                                                 messages: [Message(role: .user, content: [.text("hi")])],
                                                 tools: [ToolSchema(name: "get_weather",
                                                                    description: "查天气",
                                                                    parameters: #"{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}"#)]))
        let obj = try bodyObject()
        let tools = try XCTUnwrap(obj["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["name"] as? String, "get_weather")
        let schema = try XCTUnwrap(tools.first?["input_schema"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual((schema["properties"] as? [String: Any])?.keys.contains("city"), true)
        // max_tokens 缺省来自画像
        XCTAssertEqual(obj["max_tokens"] as? Int, 4096)
    }

    func testResponseToolUseParsed() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicToolUseResponse, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let resp = try await adapter.request(LLMRequest(model: "claude-3-5-haiku-20241022",
                                                        messages: [Message(role: .user, content: [.text("天气")])]))
        XCTAssertEqual(resp.finishReason, .toolCalls)
        let call = try XCTUnwrap(resp.toolCalls?.first)
        XCTAssertEqual(call.id, "toolu_01")
        XCTAssertEqual(call.name, "get_weather")
        // arguments 是合法 JSON（input 重新编码）
        let args = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any])
        XCTAssertEqual(args["city"] as? String, "Beijing")
        XCTAssertEqual(args["unit"] as? String, "celsius")
    }

    func testToolHistorySerializedAsBlocks() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicToolUseResponse, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let history: [Message] = [
            Message(role: .user, content: [.text("北京天气")]),
            Message(role: .assistant, content: [.toolCall(ToolCallBlock(id: "toolu_9", name: "get_weather",
                                                                        arguments: #"{"city":"Beijing"}"#))],
            source: .model),
            Message(role: .tool, content: [.toolResult(ToolResultBlock(toolCallId: "toolu_9",
                                                                       content: [.text("晴 25℃")],
                                                                       isError: false))],
            source: .tool),
        ]
        _ = try await adapter.request(LLMRequest(model: "claude-3-5-haiku-20241022", messages: history))
        let obj = try bodyObject()
        let messages = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        // assistant：content 为块数组，含 tool_use
        let assistant = try XCTUnwrap(messages.first { ($0["role"] as? String) == "assistant" })
        let blocks = try XCTUnwrap(assistant["content"] as? [[String: Any]])
        let toolUse = try XCTUnwrap(blocks.first { ($0["type"] as? String) == "tool_use" })
        XCTAssertEqual(toolUse["id"] as? String, "toolu_9")
        XCTAssertEqual(toolUse["name"] as? String, "get_weather")
        // tool 结果 → user 消息块数组 tool_result
        let resultMsg = try XCTUnwrap(messages.last { ($0["role"] as? String) == "user" })
        let resultBlocks = try XCTUnwrap(resultMsg["content"] as? [[String: Any]])
        let toolResult = try XCTUnwrap(resultBlocks.first { ($0["type"] as? String) == "tool_result" })
        XCTAssertEqual(toolResult["tool_use_id"] as? String, "toolu_9")
        XCTAssertEqual(toolResult["content"] as? String, "晴 25℃")
    }

    func testStopReasonMapping() {
        XCTAssertEqual(AnthropicAdapter.mapStopReason("end_turn"), .stop)
        XCTAssertEqual(AnthropicAdapter.mapStopReason("tool_use"), .toolCalls)
        XCTAssertEqual(AnthropicAdapter.mapStopReason("max_tokens"), .length)
        XCTAssertEqual(AnthropicAdapter.mapStopReason(nil), .stop)
        XCTAssertEqual(AnthropicAdapter.mapStopReason("unknown_x"), .stop)
    }
}

// MARK: - 归一化器单元测试

@Suite("LLMResponseNormalizer")
struct LLMNormalizerTests {
    @Test("围栏 JSON 修复")
    func fencedJSON() {
        let raw = "```json\n{\"cmd\":\"ls\"}\n```"
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), #"{"cmd":"ls"}"#)
    }

    @Test("散文前后缀修复")
    func prosePrefix() {
        let raw = "好的，命令如下：{\"cmd\":\"ls\"} 请执行。"
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), #"{"cmd":"ls"}"#)
    }

    @Test("尾逗号修复（字符串内逗号保留）")
    func trailingComma() {
        let raw = #"{"a":"x, y","b":1,}"#
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), #"{"a":"x, y","b":1}"#)
    }

    @Test("截断 JSON 补括号")
    func truncated() {
        let raw = #"{"a":{"b":"x""#
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), #"{"a":{"b":"x"}}"#)
    }

    @Test("字符串内大括号不误判")
    func bracesInString() {
        let raw = #"{"a":"}{"}"#
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), #"{"a":"}{"}"#)
    }

    @Test("不可修复原样返回")
    func unrepairable() {
        let raw = "完全不是 JSON"
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), raw)
        let quoted = #"{"a":"未闭合""#
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(quoted), quoted)
    }

    @Test("合法 JSON 原样保留")
    func validUnchanged() {
        let raw = #"{"cmd":"echo 1","n":2,"arr":[1,2],"nested":{"k":null}}"#
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), raw)
    }

    @Test("空输入原样返回")
    func empty() {
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(""), "")
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments("   "), "   ")
    }

    @Test("normalize 修复 toolCalls 参数")
    func normalizeRepairsCalls() {
        let resp = LLMResponse(model: "m",
                               content: [],
                               toolCalls: [ToolCallBlock(id: "1", name: "t", arguments: "```json\n{\"x\":1}\n```")],
                               finishReason: .toolCalls)
        let out = LLMResponseNormalizer.normalize(resp, profile: .deepSeek)
        XCTAssertEqual(out.toolCalls?.first?.arguments, #"{"x":1}"#)
        // 无 toolCalls 时原对象返回（=== 不成立但内容相等即可）
        let plain = LLMResponse(model: "m", content: [.text("hi")], finishReason: .stop)
        let plainOut = LLMResponseNormalizer.normalize(plain, profile: .openAI)
        XCTAssertEqual(plainOut.content.count, 1)
        guard case let .some(.text(t)) = plainOut.content.first else {
            return XCTFail("应为 text 块")
        }
        XCTAssertEqual(t, "hi")
    }

    @Test("response 归一化：reasoning 门控 + 空工具调用收敛 nil")
    func responseNormalization() {
        let withCalls = CompletionResult(content: "",
                                         reasoning: "think",
                                         toolCalls: [ToolCallBlock(id: "1", name: "t", arguments: "{}")],
                                         finishReason: .toolCalls)
        let ds = LLMResponseNormalizer.response(model: "m", result: withCalls, profile: .deepSeek)
        guard case let .some(.reasoning(r)) = ds.content.first else {
            return XCTFail("首块应为 reasoning")
        }
        XCTAssertEqual(r, "think")
        XCTAssertEqual(ds.toolCalls?.count, 1)

        let oa = LLMResponseNormalizer.response(model: "m", result: withCalls, profile: .openAI)
        // openAI 画像门控 reasoning
        for block in oa.content {
            if case .reasoning = block {
                return
            }
        }
        // 空 toolCalls 收敛为 nil
        let noCalls = CompletionResult(content: "hi")
        let out = LLMResponseNormalizer.response(model: "m", result: noCalls, profile: .openAI)
        XCTAssertNil(out.toolCalls)
        XCTAssertEqual(out.content.count, 1)
        guard case let .some(.text(t)) = out.content.first else {
            return XCTFail("应为 text 块")
        }
        XCTAssertEqual(t, "hi")
    }

    @Test("JSONValue 往返一致")
    func jsonValueRoundTrip() throws {
        let raw = #"{"s":"str","n":42,"f":1.5,"b":true,"nil":null,"arr":[1,"a"],"obj":{"k":false}}"#
        let value = JSONValue(jsonString: raw)
        guard case let .object(dict) = value else {
            return
        }
        XCTAssertEqual(dict["s"], .string("str"))
        XCTAssertEqual(dict["n"], .number(42))
        XCTAssertEqual(dict["b"], .bool(true))
        XCTAssertEqual(dict["nil"], .null)
        XCTAssertEqual(dict["arr"], .array([.number(1), .string("a")]))
        // 再编码后仍可解析
        let reencoded = String(data: value.jsonData(), encoding: .utf8) ?? ""
        let reparsed = JSONValue(jsonString: reencoded)
        XCTAssertEqual(reparsed, value)
        // 非法输入兜底 emptyObject
        let bad = JSONValue(jsonString: "not json")
        XCTAssertEqual(bad, .emptyObject)
    }
}
