import Foundation
import LLM
import XCTest

// MARK: - Wire 映射分支审计（LLM 包：消息序列化 / 参数修复 / 默认能力）

/// 不覆写 checkConnection 的桩 provider — 验证 LLMProvider 协议默认实现
private struct DefaultCheckProviderStub: LLMProvider {
    let id = "stub-default-check"
    let supportedModels: [String] = ["stub"]

    func request(_: LLMRequest) async throws -> LLMResponse {
        throw LLMError.networkError("stub: 不应被调用")
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

final class LLMMappingBranchTests: XCTestCase {
    private let base = URL(string: "http://stub.local/v1")!

    override func setUp() {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    /// 取最后一次请求体中的 wire messages 数组
    private func requestMessages() throws -> [[String: Any]] {
        let body = String(data: StubURLProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        return try XCTUnwrap(obj["messages"] as? [[String: Any]])
    }

    // MARK: - Anthropic 映射分支

    /// assistant 纯文本 → content 为纯字符串（非块数组）
    func testAnthropicAssistantTextEncodesAsString() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .user, content: [.text("hi")]),
                                                            Message(role: .assistant, content: [.text("已回复")], source: .model)]))
        let msgs = try requestMessages()
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[1]["role"] as? String, "assistant")
        XCTAssertEqual(msgs[1]["content"] as? String, "已回复")
        XCTAssertNil(msgs[1]["content"] as? [[String: Any]])
    }

    /// assistant 纯 reasoning → 整条消息被省略（协议不接受 reasoning 块）
    func testAnthropicAssistantReasoningOnlyOmitted() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .user, content: [.text("hi")]),
                                                            Message(role: .assistant, content: [.reasoning("思考中")], source: .model)]))
        let msgs = try requestMessages()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0]["role"] as? String, "user")
    }

    /// assistant 文本 + toolCall → content 块数组 [text, tool_use]（input 为解析后的 JSON 对象）
    func testAnthropicAssistantTextAndToolCallBlockArray() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let call = ToolCallBlock(id: "tc1", name: "search", arguments: #"{"q":"x"}"#)
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .user, content: [.text("查一下")]),
                                                            Message(role: .assistant, content: [.text("让我查一下"), .toolCall(call)], source: .model)]))
        let msgs = try requestMessages()
        let blocks = try XCTUnwrap(msgs[1]["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual(blocks[0]["text"] as? String, "让我查一下")
        XCTAssertEqual(blocks[1]["type"] as? String, "tool_use")
        XCTAssertEqual(blocks[1]["id"] as? String, "tc1")
        XCTAssertEqual(blocks[1]["name"] as? String, "search")
        let input = blocks[1]["input"] as? [String: Any]
        XCTAssertEqual(input?.count, 1)
        XCTAssertEqual(input?["q"] as? String, "x")
    }

    /// tool 结果消息（toolResult + 附加文本）→ user 消息块数组 [tool_result, text]
    func testAnthropicToolResultWithTextBlockArray() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: anthropicBody, contentType: "application/json") }
        let adapter = AnthropicAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let result = ToolResultBlock(toolCallId: "tc1", content: [.text("结果")], isError: false)
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .tool, content: [.toolResult(result), .text("补充说明")], source: .tool)]))
        let msgs = try requestMessages()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0]["role"] as? String, "user")
        let blocks = try XCTUnwrap(msgs[0]["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "tool_result")
        XCTAssertEqual(blocks[0]["tool_use_id"] as? String, "tc1")
        XCTAssertEqual(blocks[0]["content"] as? String, "结果")
        XCTAssertEqual(blocks[1]["type"] as? String, "text")
        XCTAssertEqual(blocks[1]["text"] as? String, "补充说明")
    }

    // MARK: - OpenAI 兼容映射分支

    /// assistant 纯 reasoning → 省略（不回传厂商协议不接受的块）
    func testOpenAIAssistantReasoningOnlyOmitted() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .user, content: [.text("hi")]),
                                                            Message(role: .assistant, content: [.reasoning("思考")], source: .model)]))
        let msgs = try requestMessages()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0]["role"] as? String, "user")
    }

    /// systemPrompt 置于首条 system 消息；.system 文本并入序列；纯 reasoning 的 .system 省略
    func testOpenAISystemPromptFirstAndReasoningSystemOmitted() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .system, content: [.text("角色")]),
                                                            Message(role: .system, content: [.reasoning("x")]),
                                                            Message(role: .user, content: [.text("hi")])],
                                                 systemPrompt: "SP"))
        let msgs = try requestMessages()
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs[0]["role"] as? String, "system")
        XCTAssertEqual(msgs[0]["content"] as? String, "SP")
        XCTAssertEqual(msgs[1]["role"] as? String, "system")
        XCTAssertEqual(msgs[1]["content"] as? String, "角色")
        XCTAssertEqual(msgs[2]["role"] as? String, "user")
    }

    /// tool 结果仅含 image 块 → contentText 为空串（非文本块不参与拼接）
    func testOpenAIToolResultImageOnlyYieldsEmptyContent() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: okCompletion, contentType: "application/json") }
        let adapter = OpenAIAdapter(apiKey: "k", baseURL: base, session: makeStubSession())
        let img = ImageBlock(mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let result = ToolResultBlock(toolCallId: "tc9", content: [.image(img)], isError: false)
        _ = try await adapter.request(LLMRequest(model: "m",
                                                 messages: [Message(role: .tool, content: [.toolResult(result)], source: .tool)]))
        let msgs = try requestMessages()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0]["role"] as? String, "tool")
        XCTAssertEqual(msgs[0]["content"] as? String, "")
        XCTAssertEqual(msgs[0]["tool_call_id"] as? String, "tc9")
    }

    // MARK: - Normalizer：参数修复分支

    /// 字符串内转义引号 + 尾随逗号（逗号后带空白）→ 仅去逗号，转义串原样保留
    func testRepairTrailingCommaWithEscapedQuote() {
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(#"{"q": "a\"b", }"#),
                       #"{"q": "a\"b" }"#)
    }

    /// 截断（缺右括号）+ 字符串内转义引号 → stringMask 正确识别串边界并补齐括号
    func testRepairTruncatedWithEscapedQuote() {
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(#"{"q": "a\"b", "x": 1"#),
                       #"{"q": "a\"b", "x": 1}"#)
    }

    /// 截断在字符串内部（引号不平衡）→ 不可修复，原样返回
    func testRepairUnrepairableReturnsRaw() {
        let raw = #"{"q": "a"#
        XCTAssertEqual(LLMResponseNormalizer.repairToolArguments(raw), raw)
    }

    /// normalize：修复既有响应的工具参数；无工具调用时原样返回（含 id 保持）
    func testNormalizeResponseRepairsToolArguments() {
        let broken = LLMResponse(model: "m",
                                 content: [.text("ok")],
                                 toolCalls: [ToolCallBlock(id: "t1", name: "f", arguments: #"{"a":1, }"#)],
                                 finishReason: .toolCalls)
        let fixed = LLMResponseNormalizer.normalize(broken, profile: .mock)
        XCTAssertEqual(fixed.toolCalls?.count, 1)
        XCTAssertEqual(fixed.toolCalls?.first?.arguments, #"{"a":1 }"#)

        let plain = LLMResponse(model: "m", content: [.text("ok")], finishReason: .stop)
        let passed = LLMResponseNormalizer.normalize(plain, profile: .mock)
        XCTAssertNil(passed.toolCalls)
        XCTAssertEqual(passed.id, plain.id)
    }

    // MARK: - Normalizer：JSONValue 解码 + 内容块门控 + 响应构造

    /// JSONValue 全 case 解码（转义引号串/数值/布尔/null/数组）+ 非法输入兜底 emptyObject
    func testJSONValueDecodesAllCasesAndFallsBack() {
        let v = JSONValue(jsonString: #"{"s":"x\"y","n":1.5,"b":true,"z":null,"a":[1,"t","f"]}"#)
        guard case let .object(o) = v else {
            return XCTFail("应为 object：\(v)")
        }
        XCTAssertEqual(o["s"], .string(#"x"y"#))
        XCTAssertEqual(o["n"], .number(1.5))
        XCTAssertEqual(o["b"], .bool(true))
        XCTAssertEqual(o["z"], .null)
        XCTAssertEqual(o["a"], .array([.number(1.0), .string("t"), .string("f")]))
        XCTAssertEqual(JSONValue(jsonString: "不是 JSON"), .emptyObject)
        XCTAssertEqual(JSONValue(jsonString: ""), .emptyObject)
    }

    /// contentBlocks：reasoning 块按画像门控（deepSeek 开 / openAI 关）；空内容收敛为空数组
    func testContentBlocksGatedByProfile() {
        let result = CompletionResult(content: "c", reasoning: "r")
        let gatedOn = LLMResponseNormalizer.contentBlocks(result: result, profile: .deepSeek)
        XCTAssertEqual(gatedOn.count, 2)
        if case let .reasoning(r)? = gatedOn.first {
            XCTAssertEqual(r, "r")
        } else {
            XCTFail("首块应为 reasoning")
        }
        if case let .text(t)? = gatedOn.last {
            XCTAssertEqual(t, "c")
        } else {
            XCTFail("末块应为 text")
        }

        let gatedOff = LLMResponseNormalizer.contentBlocks(result: result, profile: .openAI)
        XCTAssertEqual(gatedOff.count, 1)
        if case let .text(t)? = gatedOff.first {
            XCTAssertEqual(t, "c")
        } else {
            XCTFail("应为 text 块")
        }

        XCTAssertTrue(LLMResponseNormalizer.contentBlocks(result: CompletionResult(content: ""), profile: .deepSeek).isEmpty)
    }

    /// response 构造：工具参数修复入参 + usage/finishReason 透传；空工具调用收敛为 nil
    func testResponseBuildRepairsArguments() {
        let result = CompletionResult(content: "ok",
                                      toolCalls: [ToolCallBlock(id: "t1", name: "f", arguments: #"{"a":1, }"#)],
                                      finishReason: .toolCalls,
                                      usage: TokenUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3))
        let resp = LLMResponseNormalizer.response(model: "m", result: result, profile: .mock)
        XCTAssertEqual(resp.toolCalls?.count, 1)
        XCTAssertEqual(resp.toolCalls?.first?.arguments, #"{"a":1 }"#)
        XCTAssertEqual(resp.finishReason, .toolCalls)
        XCTAssertEqual(resp.usage?.totalTokens, 3)

        let noCalls = LLMResponseNormalizer.response(model: "m", result: CompletionResult(content: "hi"), profile: .mock)
        XCTAssertNil(noCalls.toolCalls)
    }

    // MARK: - 协议默认能力

    /// LLMProvider.checkConnection 默认实现：不支持连接测试的 provider 抛 networkError
    func testProviderDefaultCheckConnectionThrows() async {
        do {
            _ = try await DefaultCheckProviderStub().checkConnection()
            XCTFail("应当抛出 networkError")
        } catch let e as LLMError {
            guard case let .networkError(detail) = e else {
                return XCTFail("错误类型不符：\(e)")
            }
            XCTAssertEqual(detail, "该提供商不支持连接测试")
        } catch {
            XCTFail("意外错误：\(error)")
        }
    }
}
