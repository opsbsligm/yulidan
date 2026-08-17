import Agent
import Foundation
import LLM
import Session
import Subagent
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
        // 4 × 0.3s 两两并行 ≈ 0.6s，给足上下限余量
        XCTAssertGreaterThanOrEqual(elapsed, 0.55)
        XCTAssertLessThan(elapsed, 1.4)
    }

    func testTimeoutMarksTimedOutAndCancelsAgent() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = MockAgent(delay: 1.0)
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "slow", task: "x", timeout: 0.3))
        let start = Date()
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .timedOut)
        XCTAssertTrue(state.error?.contains("未响应") == true)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.9)
        let cancelCount = await agent.cancelCount
        XCTAssertEqual(cancelCount, 1)
    }

    func testCancelRunningSubagent() async throws {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let agent = MockAgent(delay: 10)
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: "long", task: "x", timeout: 60))
        try await Task.sleep(nanoseconds: 150_000_000)
        await coordinator.cancel(id)
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertLessThan(state.elapsed ?? 99, 0.9)
        let cancelCount = await agent.cancelCount
        XCTAssertEqual(cancelCount, 1)
    }

    func testCancelWhilePendingIsRespected() async throws {
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let blocker = MockAgent(delay: 0.6)
        let slow = MockAgent(delay: 10)
        let blockID = await coordinator.spawn(agent: blocker, spec: SubagentSpec(name: "blocker", task: "x"))
        let slowID = await coordinator.spawn(agent: slow, spec: SubagentSpec(name: "slow", task: "x", timeout: 60))
        try await Task.sleep(nanoseconds: 100_000_000)
        // slow 还在排队（pending），取消后不应执行
        await coordinator.cancel(slowID)
        let slowState = await coordinator.waitFor(slowID)
        XCTAssertEqual(slowState.phase, .cancelled)
        let slowSent = await slow.sentCount
        XCTAssertEqual(slowSent, 0)
        _ = await coordinator.waitFor(blockID)
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
        // 等待事件回调落盘
        try await Task.sleep(nanoseconds: 100_000_000)
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
