import Agent
import Foundation
import LLM
import ServiceContainer
import Session
import Testing
import Tools
import XCTest

// MARK: - 桩工具

/// 执行计数（验证是否真正执行）
actor ExecCounter {
    private(set) var count = 0
    func bump() {
        count += 1
    }
}

/// 失败开关（熔断恢复测试用）
actor FailureGate {
    private(set) var shouldFail = true
    func setFail(_ value: Bool) {
        shouldFail = value
    }

    func isFailing() -> Bool {
        shouldFail
    }
}

struct EchoStubTool: Tool {
    let name = "echo"
    let description = "回显 text 参数"
    let parameterSchema = "{}"
    let requiredParameters = ["text"]
    let counter: ExecCounter?

    init(counter: ExecCounter? = nil) {
        self.counter = counter
    }

    func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        await counter?.bump()
        return ToolResult(content: [.text(args["text"] ?? "")])
    }
}

struct MultiBlockStubTool: Tool {
    let name = "multi_tool"
    let description = "混合多块输出工具"
    let parameterSchema = "{}"

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [
            .text("12345"),
            .image(ImageBlock(mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x4E]))),
            .text(String(repeating: "y", count: 30)),
        ])
    }
}

struct JSONWithNoiseStubTool: Tool {
    let name = "json_noise_tool"
    let description = "带 reasoning 噪声的 JSON 输出工具"
    let parameterSchema = "{}"
    let validatesJSONOutput = true

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text(#"{"ok":1}"#), .reasoning("noise")])
    }
}

struct SlowStubTool: Tool {
    let name = "slow_tool"
    let description = "慢工具"
    let parameterSchema = "{}"
    let delay: TimeInterval
    let counter: ExecCounter?

    init(delay: TimeInterval, counter: ExecCounter? = nil) {
        self.delay = delay
        self.counter = counter
    }

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        await counter?.bump()
        // 协作式取消：超时后任务被取消时 sleep 立即返回，不残留
        try? await Task.sleep(for: .seconds(delay))
        return ToolResult(content: [.text("slow done")])
    }
}

struct FlakyStubTool: Tool {
    let name = "flaky_tool"
    let description = "可切换失败的工具"
    let parameterSchema = "{}"
    let gate: FailureGate
    let counter: ExecCounter

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        await counter.bump()
        if await gate.isFailing() {
            throw NSError(domain: "flaky", code: 42, userInfo: [NSLocalizedDescriptionKey: "模拟失败"])
        }
        return ToolResult(content: [.text("recovered")])
    }
}

struct BigStubTool: Tool {
    let name = "big_tool"
    let description = "大输出工具"
    let parameterSchema = "{}"
    let size: Int

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text(String(repeating: "x", count: size))])
    }
}

struct JSONStubTool: Tool {
    let name = "json_tool"
    let description = "JSON 输出工具"
    let parameterSchema = "{}"
    let validatesJSONOutput = true
    let output: String

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text(output)])
    }
}

struct ChunkyStubTool: Tool {
    let name = "chunky_tool"
    let description = "流式进度工具"
    let parameterSchema = "{}"

    func execute(_: [String: String], context: ToolRunContext) async throws -> ToolResult {
        context.onChunk?("块1")
        context.onChunk?("块2")
        context.onChunk?("块3")
        return ToolResult(content: [.text("done")])
    }
}

/// 轮询直到条件满足或超时（替代固定 sleep，防事件循环调度抖动导致瞬态失败）
/// 默认窗口 5s：macOS 27 beta 存在瞬态协作池调度停滞（~10-13s；证据见 QUALITY_REPORT P1）
private func eventually(_ timeout: TimeInterval = 5, _ condition: @escaping () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

actor ExecEventBox {
    private(set) var events: [ToolExecEvent] = []
    func append(_ event: ToolExecEvent) {
        events.append(event)
    }
}

// MARK: - 测试

final class ToolExecutorTests: XCTestCase {
    private func text(_ r: ToolResult) -> String {
        r.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined()
    }

    func testUnknownToolReturnsCode() async {
        let executor = ToolExecutor()
        let registry = ToolRegistry()
        let result = await executor.execute(ToolCall(name: "ghost"), in: registry)
        XCTAssertEqual(result.error?.code, "unknown_tool")
        XCTAssertTrue(text(result).contains("ghost"))
    }

    func testMissingRequiredRejectedWithoutExecution() async {
        let counter = ExecCounter()
        let executor = ToolExecutor()
        let registry = ToolRegistry()
        await registry.register(EchoStubTool(counter: counter))
        let result = await executor.execute(ToolCall(name: "echo", arguments: [:]), in: registry)
        XCTAssertEqual(result.error?.code, "invalid_args")
        XCTAssertTrue(text(result).contains("text"))
        let n = await counter.count
        XCTAssertEqual(n, 0, "参数校验必须在执行前拦截")
    }

    func testBlankArgumentTreatedAsMissing() async {
        let executor = ToolExecutor()
        let registry = ToolRegistry()
        await registry.register(EchoStubTool())
        let result = await executor.execute(ToolCall(name: "echo", arguments: ["text": "   "]), in: registry)
        XCTAssertEqual(result.error?.code, "invalid_args")
    }

    func testTimeoutReturnsTimeoutCode() async {
        let counter = ExecCounter()
        let executor = ToolExecutor(policy: .init(defaultTimeout: 0.3))
        let registry = ToolRegistry()
        await registry.register(SlowStubTool(delay: 5, counter: counter))
        let start = Date()
        let result = await executor.execute(ToolCall(name: "slow_tool"), in: registry)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.error?.code, "timeout")
        XCTAssertLessThan(elapsed, 2, "超时必须立即返回，不能等满 5s")
        let n = await counter.count
        XCTAssertEqual(n, 1, "工具确实被启动过")
    }

    func testPerToolTimeoutOverride() async {
        let executor = ToolExecutor(policy: .init(defaultTimeout: 60, timeouts: ["slow_tool": 0.3]))
        let registry = ToolRegistry()
        await registry.register(SlowStubTool(delay: 5))
        let start = Date()
        let result = await executor.execute(ToolCall(name: "slow_tool"), in: registry)
        XCTAssertEqual(result.error?.code, "timeout")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testBreakerOpensAfterConsecutiveFailures() async {
        let gate = FailureGate()
        let counter = ExecCounter()
        let executor = ToolExecutor(policy: .init(breakerFailureThreshold: 2, breakerResetTimeout: 60))
        let registry = ToolRegistry()
        await registry.register(FlakyStubTool(gate: gate, counter: counter))

        let r1 = await executor.execute(ToolCall(name: "flaky_tool"), in: registry)
        XCTAssertEqual(r1.error?.code, "exec_failed")
        let r2 = await executor.execute(ToolCall(name: "flaky_tool"), in: registry)
        XCTAssertEqual(r2.error?.code, "exec_failed")
        // 第 3 次：熔断打开，不再执行
        let r3 = await executor.execute(ToolCall(name: "flaky_tool"), in: registry)
        XCTAssertEqual(r3.error?.code, "circuit_open")
        let n = await counter.count
        XCTAssertEqual(n, 2, "熔断后不得再执行工具")
    }

    func testBreakerRecoversAfterReset() async throws {
        let gate = FailureGate()
        let counter = ExecCounter()
        let executor = ToolExecutor(policy: .init(breakerFailureThreshold: 1, breakerResetTimeout: 0.2))
        let registry = ToolRegistry()
        await registry.register(FlakyStubTool(gate: gate, counter: counter))

        _ = await executor.execute(ToolCall(name: "flaky_tool"), in: registry) // 失败 → open
        let r2 = await executor.execute(ToolCall(name: "flaky_tool"), in: registry)
        XCTAssertEqual(r2.error?.code, "circuit_open")
        try await Task.sleep(for: .seconds(0.3)) // open → half-open
        await gate.setFail(false)
        let r3 = await executor.execute(ToolCall(name: "flaky_tool"), in: registry)
        XCTAssertNil(r3.error)
        XCTAssertTrue(text(r3).contains("recovered"))
    }

    func testBigOutputTruncated() async {
        let executor = ToolExecutor(policy: .init(maxOutputCharacters: 1000))
        let registry = ToolRegistry()
        await registry.register(BigStubTool(size: 5000))
        let result = await executor.execute(ToolCall(name: "big_tool"), in: registry)
        XCTAssertNil(result.error)
        let t = text(result)
        XCTAssertTrue(t.contains("输出截断"))
        XCTAssertLessThan(t.count, 1200, "截断后应接近上限（含标记）")
        XCTAssertEqual(result.meta?["truncated"], "true")
    }

    // MARK: - 截断分支与非文本块路径（覆盖审计轮）

    /// 截断 map：非文本块原样穿过 + 限内文本块整体保留 + 超限文本块截断带标记
    func testTruncationSkipsNonTextAndKeepsFittingBlocks() async {
        let executor = ToolExecutor(policy: .init(maxOutputCharacters: 10))
        let registry = ToolRegistry()
        await registry.register(MultiBlockStubTool())
        let result = await executor.execute(ToolCall(name: "multi_tool"), in: registry)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.content.count, 3, "块数不变，仅文本内容截断")
        if case let .text(t1) = result.content[0] {
            XCTAssertEqual(t1, "12345", "限内文本块应整体保留")
        } else {
            XCTFail("首块应为原样文本")
        }
        if case .image = result.content[1] {} else {
            XCTFail("第二块应为 image 原样穿过")
        }
        if case let .text(t3) = result.content[2] {
            XCTAssertTrue(t3.hasPrefix("yyyyy"), "应保留剩余配额内的前缀")
            XCTAssertTrue(t3.contains("输出截断"), "应带截断标记")
        } else {
            XCTFail("第三块应为截断文本")
        }
        XCTAssertEqual(result.meta?["truncated"], "true")
    }

    /// textOf/textCharCount 仅统计 text 块（非文本块走 nil 分支）：reasoning 噪声不干扰 JSON 校验
    func testJSONValidationIgnoresNonTextBlocks() async {
        let executor = ToolExecutor()
        let registry = ToolRegistry()
        await registry.register(JSONWithNoiseStubTool())
        let result = await executor.execute(ToolCall(name: "json_noise_tool"), in: registry)
        XCTAssertNil(result.error, "reasoning 块不应参与 JSON 校验/字符计数")
    }

    func testJSONOutputInvalidRejected() async {
        let executor = ToolExecutor()
        let registry = ToolRegistry()
        await registry.register(JSONStubTool(output: "这不是 JSON"))
        let result = await executor.execute(ToolCall(name: "json_tool"), in: registry)
        XCTAssertEqual(result.error?.code, "output_invalid")
    }

    func testJSONOutputValidPasses() async {
        let executor = ToolExecutor()
        let registry = ToolRegistry()
        await registry.register(JSONStubTool(output: #"{"a":1}"#))
        let result = await executor.execute(ToolCall(name: "json_tool"), in: registry)
        XCTAssertNil(result.error)
    }

    func testEventsEmittedOnSuccess() async throws {
        let box = ExecEventBox()
        let executor = ToolExecutor()
        executor.onEvent = { event in
            Task { await box.append(event) }
        }
        let registry = ToolRegistry()
        await registry.register(EchoStubTool())
        let result = await executor.execute(ToolCall(name: "echo", arguments: ["text": "hi"]), in: registry)
        XCTAssertNil(result.error)
        let gotTwo = await eventually { await box.events.count == 2 }
        XCTAssertTrue(gotTwo, "3 秒内应发出 started/finished 两个事件")
        let events = await box.events
        XCTAssertEqual(events.count, 2)
        if case let .started(name) = events[0] {
            XCTAssertEqual(name, "echo")
        } else {
            XCTFail("首事件应为 started")
        }
        if case let .finished(name, duration, isError) = events[1] {
            XCTAssertEqual(name, "echo")
            XCTAssertFalse(isError)
            XCTAssertGreaterThanOrEqual(duration, 0)
        } else {
            XCTFail("次事件应为 finished")
        }
    }

    func testOnChunkStreamingPassedThrough() async {
        let chunks = OrderedChunkCollector()
        let executor = ToolExecutor()
        let registry = ToolRegistry()
        await registry.register(ChunkyStubTool())
        let context = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:],
                                     onChunk: { chunk in
                                         // 同步收集（锁保护，保持 onChunk 调用顺序）；
                                         // 用 Task 包装会丢失顺序保证，高负载下乱序 flake
                                         chunks.append(chunk)
                                     })
        let result = await executor.execute(ToolCall(name: "chunky_tool"), in: registry, context: context)
        XCTAssertNil(result.error)
        XCTAssertEqual(chunks.all, ["块1", "块2", "块3"])
    }
}

/// 顺序块收集器：onChunk 是同步回调，按调用序追加（NSLock 保护跨线程可见性）
final class OrderedChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func append(_ s: String) {
        lock.lock()
        items.append(s)
        lock.unlock()
    }
}

actor ChunkCollector {
    private(set) var all: [String] = []
    func append(_ s: String) {
        all.append(s)
    }
}
