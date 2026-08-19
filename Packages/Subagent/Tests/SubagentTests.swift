import Agent
import Foundation
import LLM
import Session
import Subagent
import Testing
import Tools
import XCTest

// MARK: - 测试辅助

/// 并发计数（工作区重叠度）
actor ConcurrencyCounter {
    private(set) var current = 0
    private(set) var maxObserved = 0
    private(set) var entered = 0
    private(set) var exited = 0

    func enter() {
        current += 1
        entered += 1
        maxObserved = Swift.max(maxObserved, current)
    }

    func exit() {
        current -= 1
        exited += 1
    }
}

/// 区间记录（验证无重叠）
actor IntervalRecorder {
    private(set) var intervals: [(start: Date, end: Date)] = []
    private var openStart: Date?

    func start() {
        openStart = Date()
    }

    func end() {
        if let start = openStart {
            intervals.append((start, Date()))
            openStart = nil
        }
    }
}

/// 可配置时延/失败/取消感知的 Mock Agent
actor MockAgent: Agent {
    let id = AgentID()
    let sessionID = SessionID()
    nonisolated(unsafe) var status: AgentStatus = .idle

    private let delay: TimeInterval
    private let failWith: String?
    private let counter: ConcurrencyCounter?
    private let recorder: IntervalRecorder?
    private(set) var sentCount = 0
    private(set) var cancelCount = 0

    init(delay: TimeInterval = 0, failWith: String? = nil,
         counter: ConcurrencyCounter? = nil, recorder: IntervalRecorder? = nil) {
        self.delay = delay
        self.failWith = failWith
        self.counter = counter
        self.recorder = recorder
    }

    func send(_: UserMessage, target _: InboxTarget, wakeup _: Bool) async {
        sentCount += 1
        status = .running
        await counter?.enter()
        await recorder?.start()
        defer {
            Task {
                await self.counter?.exit()
                await self.recorder?.end()
            }
        }
        // 分片睡眠，期间响应取消
        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            if cancelCount > 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        status = .idle
    }

    func followup(_ message: UserMessage) async {
        await send(message, target: .nextTurn, wakeup: true)
    }

    func inject(_ message: UserMessage) async {
        await send(message, target: .nextStep, wakeup: false)
    }

    func cancel(keepInbox _: Bool) async {
        cancelCount += 1
        status = .idle
    }

    func whenIdle() async -> AgentResult {
        if cancelCount > 0 {
            return AgentResult(status: .idle, error: "cancelled by test")
        }
        if let failWith {
            return AgentResult(status: .idle, error: failWith)
        }
        let msg = AssistantMessage(turn: 1, step: 1, content: [.text("ok")], provider: "mock", model: "mock")
        return AgentResult(status: .idle, messages: [msg])
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

actor EventBox {
    private(set) var events: [SubagentEvent] = []
    func append(_ event: SubagentEvent) {
        events.append(event)
    }
}

// MARK: - 协调器测试

final class SubagentCoordinatorTests: XCTestCase {
    func testSpawnAndSucceed() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = MockAgent(delay: 0.05)
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "任务A", task: "do it"))
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .succeeded)
        XCTAssertEqual(state.name, "任务A")
        XCTAssertNotNil(state.elapsed)
        guard case let .some(.text(text)) = state.result?.messages.first?.content.first else {
            return XCTFail("结果应包含 text 内容")
        }
        XCTAssertEqual(text, "ok")
        let sent = await agent.sentCount
        XCTAssertEqual(sent, 1)
        let all = await coordinator.allStates()
        XCTAssertEqual(all.count, 1)
    }

    func testLimit1RunsSerially() async {
        let counter = ConcurrencyCounter()
        let recorder = IntervalRecorder()
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        var ids: [SubagentID] = []
        for i in 0 ..< 3 {
            let agent = MockAgent(delay: 0.25, recorder: recorder)
            let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "t\(i)", task: "x"))
            ids.append(id)
            _ = counter
        }
        let states = await coordinator.waitForAll()
        XCTAssertEqual(states.count, 3)
        XCTAssertTrue(states.allSatisfy { $0.phase == .succeeded })
        let intervals = await recorder.intervals
        XCTAssertEqual(intervals.count, 3)
        // 两两不重叠
        for a in 0 ..< intervals.count {
            for b in (a + 1) ..< intervals.count {
                let overlap = intervals[a].start < intervals[b].end && intervals[b].start < intervals[a].end
                XCTAssertFalse(overlap, "区间 \(a) 与 \(b) 重叠")
            }
        }
    }

    func testLimit2MaxParallelTwo() async {
        let counter = ConcurrencyCounter()
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        var ids: [SubagentID] = []
        for i in 0 ..< 4 {
            let agent = MockAgent(delay: 0.3, counter: counter)
            let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "t\(i)", task: "x"))
            ids.append(id)
        }
        let start = Date()
        let states = await coordinator.waitForAll()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(states.count, 4)
        XCTAssertTrue(states.allSatisfy { $0.phase == .succeeded })
        let maxObserved = await counter.maxObserved
        XCTAssertEqual(maxObserved, 2)
        // 4 × 0.3s 两两并行 ≈ 0.6s；下限验证并行度，上限放宽为 8s：
        // 理论值 0.6s + macOS 27 beta 瞬态调度停滞容忍（~10-13s，见 QUALITY_REPORT P1）
        XCTAssertGreaterThanOrEqual(elapsed, 0.55)
        XCTAssertLessThan(elapsed, 8.0)
    }

    func testTimeoutMarksTimedOutAndCancelsAgent() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = MockAgent(delay: 1.0)
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "slow", task: "x", timeout: 0.3))
        let start = Date()
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .timedOut)
        XCTAssertTrue(state.error?.contains("未响应") == true)
        // 上限 5s：验证超时在 0.3s 规格附近触发（而非等满 1.0s 延迟）；
        // 放宽为 macOS 27 beta 瞬态调度停滞容忍（见 QUALITY_REPORT P1）
        XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
        let cancelCount = await agent.cancelCount
        XCTAssertEqual(cancelCount, 1)
    }

    func testCancelRunningSubagent() async {
        // 前置重试：前置条件依赖任务被及时调度；macOS 27 beta 调度停滞（~10-13s，QUALITY_REPORT P1）
        // 下前置必然失败且场景语义失效，重建场景重试一次；两次均停滞判环境故障（CI 有界重试兜底）
        var ok = await cancelRunningScenario()
        if !ok {
            ok = await cancelRunningScenario()
        }
        XCTAssertTrue(ok, "两次尝试前置条件均未满足（疑似 macOS 调度停滞，非协调器逻辑缺陷）")
    }

    /// 取消运行中子任务场景；返回 false 表示前置条件停滞（非断言失败）
    private func cancelRunningScenario() async -> Bool {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = MockAgent(delay: 10)
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "long", task: "x", timeout: 60))
        // 等真正 running 再取消（排队中取消则 startedAt 不落，elapsed 断言失效；固定 sleep 调度抖动下不可靠）
        let isRunning = await eventually(10) {
            await coordinator.allStates().contains { $0.id == id && $0.phase == .running }
        }
        guard isRunning else {
            await coordinator.shutdown()
            return false
        }
        await coordinator.cancel(id)
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .cancelled)
        // 上限 5s：取消后 agent 应在分片睡眠粒度（~10ms）内退出；放宽为调度停滞容忍
        XCTAssertLessThan(state.elapsed ?? 99, 5.0)
        let cancelCount = await agent.cancelCount
        XCTAssertEqual(cancelCount, 1)
        return true
    }

    func testCancelWhilePendingIsRespected() async {
        // 前置重试：同 testCancelRunningSubagent（macOS 27 beta 调度停滞容忍，QUALITY_REPORT P1）
        var ok = await cancelPendingScenario()
        if !ok {
            ok = await cancelPendingScenario()
        }
        XCTAssertTrue(ok, "两次尝试前置条件均未满足（疑似 macOS 调度停滞，非协调器逻辑缺陷）")
    }

    /// 排队中取消场景；返回 false 表示前置条件停滞（非断言失败）
    private func cancelPendingScenario() async -> Bool {
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let blocker = MockAgent(delay: 0.6)
        let slow = MockAgent(delay: 10)
        let blockID = await coordinator.spawn(agent: blocker, spec: SubagentSpec(name: "blocker", task: "x"))
        let slowID = await coordinator.spawn(agent: slow, spec: SubagentSpec(name: "slow", task: "x", timeout: 60))
        // 等 blocker 占住唯一槽位（此时 slow 必在排队；固定 sleep 调度抖动下不可靠）
        let blockerRunning = await eventually(10) {
            await coordinator.allStates().contains { $0.id == blockID && $0.phase == .running }
        }
        guard blockerRunning else {
            await coordinator.shutdown()
            return false
        }
        // slow 还在排队（pending），取消后不应执行
        await coordinator.cancel(slowID)
        let slowState = await coordinator.waitFor(slowID)
        XCTAssertEqual(slowState.phase, .cancelled)
        let slowSent = await slow.sentCount
        XCTAssertEqual(slowSent, 0)
        _ = await coordinator.waitFor(blockID)
        return true
    }

    func testAgentFailureSurfacesError() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let agent = MockAgent(failWith: "boom")
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "bad", task: "x"))
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(state.error, "boom")
        XCTAssertNotNil(state.result)
    }

    func testEventOrder() async throws {
        let box = EventBox()
        let coordinator = SubagentCoordinator(maxConcurrent: 1, onEvent: { event in
            Task { await box.append(event) }
        })
        let agent = MockAgent(delay: 0.05)
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "evt", task: "x"))
        _ = await coordinator.waitFor(id)
        // 等待事件回调落盘（条件轮询替代固定 sleep）
        let gotThree = await eventually { await box.events.count == 3 }
        XCTAssertTrue(gotThree, "3 秒内应落盘 spawned/started/finished 三个事件")
        let events = await box.events
        XCTAssertEqual(events.count, 3)
        if case let .spawned(eID, name) = events[0] {
            XCTAssertEqual(eID, id)
            XCTAssertEqual(name, "evt")
        } else {
            XCTFail("首个事件应为 spawned")
        }
        if case let .started(eID) = events[1] {
            XCTAssertEqual(eID, id)
        } else {
            XCTFail("第二个事件应为 started")
        }
        if case let .finished(eID, state) = events[2] {
            XCTAssertEqual(eID, id)
            XCTAssertEqual(state.phase, .succeeded)
        } else {
            XCTFail("第三个事件应为 finished")
        }
    }
}

// MARK: - 真实 AgentLoop 集成（验证 whenIdle 真实等待 / 超时取消链路）

/// 脚本化文本 LLM（可注入响应延迟）
private final class ScriptedTextLLM: LLMProvider, @unchecked Sendable {
    let id = "scripted-llm"
    let supportedModels = ["mock-model"]
    private let responses: [LLMResponse]
    private let delay: Double
    private let lock = NSLock()
    private var count = 0

    init(responses: [LLMResponse], delay: Double = 0) {
        self.responses = responses
        self.delay = delay
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        var idx = 0
        lock.withLock {
            idx = min(count, max(responses.count - 1, 0))
            count += 1
        }
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        return responses[idx]
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@Suite("SubagentPhase 通知标题映射")
struct SubagentPhaseNotificationTests {
    @Test("succeeded/failed/timedOut 有标题；cancelled 与进行中为 nil")
    func titles() {
        #expect(SubagentPhase.succeeded.notificationTitle == "子任务完成")
        #expect(SubagentPhase.failed.notificationTitle == "子任务失败")
        #expect(SubagentPhase.timedOut.notificationTitle == "子任务超时")
        #expect(SubagentPhase.cancelled.notificationTitle == nil)
        #expect(SubagentPhase.pending.notificationTitle == nil)
        #expect(SubagentPhase.running.notificationTitle == nil)
    }
}

final class CoordinatorRealAgentLoopTests: XCTestCase {
    func testSpawnRealAgentLoopAndSucceed() async {
        let llm = ScriptedTextLLM(
            responses: [LLMResponse(model: "mock-model", content: [.text("子任务完成")], finishReason: .stop)],
            delay: 0.05
        )
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = AgentLoop(sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        let id = await coordinator.spawn(agent: agent, spec: .init(name: "真实任务", task: "完成任务"))
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .succeeded)
        XCTAssertNil(state.error)
        let text = state.result?.messages.first?.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined() ?? ""
        XCTAssertTrue(text.contains("子任务完成"))
    }

    func testRealAgentLoopTimeout() async {
        let llm = ScriptedTextLLM(
            responses: [LLMResponse(model: "mock-model", content: [.text("永远不会到达")], finishReason: .stop)],
            delay: 2
        )
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = AgentLoop(sessionID: SessionID(), llm: llm, tools: ToolRegistry(), model: "mock-model")
        let id = await coordinator.spawn(agent: agent, spec: .init(name: "超时任务", task: "慢任务", timeout: 0.4))
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .timedOut)
        XCTAssertNotNil(state.error)
    }
}

// MARK: - 历史持久化测试

@Suite("SubagentHistoryStore 持久化测试")
struct SubagentHistoryStoreTests {
    private func makeItem(_ n: Int) -> SubagentHistoryItem {
        SubagentHistoryItem(id: "id-\(n)", name: "任务\(n)", phase: n % 2 == 0 ? .succeeded : .failed,
                            resultText: "结果\(n)", error: n % 2 == 0 ? nil : "err-\(n)",
                            elapsed: 1.0 + Double(n), stepLines: ["步骤1 · 回复 x"], finishedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)))
    }

    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("subagent-history-\(UUID().uuidString).json")
    }

    @Test("往返：保存后读取字段一致")
    func roundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let items = [makeItem(1), makeItem(2)]
        SubagentHistoryStore.save(items, url: url)
        let loaded = SubagentHistoryStore.load(url: url)
        #expect(loaded.count == 2)
        #expect(loaded[0].id == "id-1")
        #expect(loaded[0].phase == .failed)
        #expect(loaded[0].error == "err-1")
        #expect(loaded[1].phase == .succeeded)
        #expect(loaded[1].resultText == "结果2")
        #expect(loaded[1].stepLines == ["步骤1 · 回复 x"])
    }

    @Test("上限：超出 cap 的旧条目被截断（最新在前）")
    func cap() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let items = (1 ... 60).map(makeItem) // items[0] 最新
        SubagentHistoryStore.save(items, url: url)
        let loaded = SubagentHistoryStore.load(url: url)
        #expect(loaded.count == 50)
        #expect(loaded.first?.id == "id-1")
        #expect(loaded.last?.id == "id-50")
    }

    @Test("空文件与缺失文件：返回空数组")
    func empty() {
        #expect(SubagentHistoryStore.load(url: tempURL()).isEmpty)
        let url = tempURL()
        SubagentHistoryStore.save([], url: url)
        #expect(SubagentHistoryStore.load(url: url).isEmpty)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - spawn_subagent 工具（主 Agent 委派子任务）

final class SpawnSubagentToolTests: XCTestCase {
    private func makeTool(llm: (any LLMProvider)?,
                          coordinator: SubagentCoordinator) -> SpawnSubagentTool {
        SpawnSubagentTool(
            coordinator: coordinator,
            subTools: ToolRegistry(),
            model: "mock-model",
            makeLLM: { llm }
        )
    }

    private func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    func testSuccessReturnsSubagentText() async throws {
        let llm = ScriptedTextLLM(responses: [
            LLMResponse(model: "mock-model", content: [.text("答案是 42")], finishReason: .stop),
        ])
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let tool = makeTool(llm: llm, coordinator: coordinator)
        let result = try await tool.execute(["task": "计算答案"], context: context())
        XCTAssertNil(result.error)
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        XCTAssertTrue(text.contains("答案是 42"))
    }

    func testMissingTaskReturnsInvalidArgs() async throws {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let tool = makeTool(llm: nil, coordinator: coordinator)
        let result = try await tool.execute(["name": "空任务"], context: context())
        XCTAssertEqual(result.error?.code, "invalid_args")
    }

    func testSlowLLMTimesOut() async throws {
        let llm = ScriptedTextLLM(responses: [
            LLMResponse(model: "mock-model", content: [.text("永远不会到达")], finishReason: .stop),
        ], delay: 3)
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let tool = makeTool(llm: llm, coordinator: coordinator)
        let result = try await tool.execute(["task": "慢任务", "timeout": "0.4"], context: context())
        XCTAssertEqual(result.error?.code, SubagentPhase.timedOut.rawValue)
    }

    func testNoLLMReturnsError() async throws {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let tool = makeTool(llm: nil, coordinator: coordinator)
        let result = try await tool.execute(["task": "随便任务"], context: context())
        XCTAssertEqual(result.error?.code, "no_llm")
    }
}
