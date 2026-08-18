import Agent
import Foundation
import LLM
import Session
import Subagent
import XCTest

// MARK: - 模块2：生命周期管理（入参下发/父子关系/完成回调/自动回收/.shutdown）

/// 记录收到的任务文本（验证结构化入参下发）
actor CapturingAgent: Agent {
    let id = AgentID()
    let sessionID = SessionID()
    nonisolated(unsafe) var status: AgentStatus = .idle

    private let delay: TimeInterval
    private(set) var received: [String] = []
    private(set) var cancelCount = 0

    init(delay: TimeInterval = 0) {
        self.delay = delay
    }

    func send(_ message: UserMessage, target _: InboxTarget, wakeup _: Bool) async {
        let text = message.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        received.append(text)
        status = .running
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
        let msg = AssistantMessage(turn: 1, step: 1, content: [.text("captured")], provider: "mock", model: "mock")
        return AgentResult(status: .idle, messages: [msg])
    }
}

/// 完成回调收集器
actor FinishedBox {
    private(set) var states: [SubagentState] = []
    func append(_ state: SubagentState) {
        states.append(state)
    }
}

final class CoordinatorLifecycleTests: XCTestCase {
    func testContextDeliveredAsSortedParams() async {
        let agent = CapturingAgent()
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let spec = SubagentSpec(name: "with-params", task: "请执行任务", timeout: 30,
                                context: ["beta": "2", "alpha": "1"])
        let id = await coordinator.spawn(agent: agent, spec: spec)
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.phase, .succeeded)
        let received = await agent.received
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received[0].hasPrefix("请执行任务"), "任务文本应在最前")
        XCTAssertTrue(received[0].contains("【输入参数】"), "应含入参段")
        // 按键排序：alpha 行在 beta 行之前
        let alphaIdx = received[0].range(of: "- alpha: 1")?.lowerBound
        let betaIdx = received[0].range(of: "- beta: 2")?.lowerBound
        XCTAssertNotNil(alphaIdx)
        XCTAssertNotNil(betaIdx)
        if let a = alphaIdx, let b = betaIdx {
            XCTAssertLessThan(a, b)
        }
    }

    func testEmptyContextDoesNotAppendParams() async {
        let agent = CapturingAgent()
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let id = await coordinator.spawn(agent: agent, spec: .init(name: "bare", task: "纯任务文本"))
        _ = await coordinator.waitFor(id)
        let received = await agent.received
        XCTAssertEqual(received.first, "纯任务文本")
    }

    func testParentIDPropagates() async {
        let parent = SubagentID()
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let id = await coordinator.spawn(agent: MockAgent(),
                                         spec: .init(name: "child", task: "x", parentID: parent))
        let state = await coordinator.waitFor(id)
        XCTAssertEqual(state.parentID, parent)
        // 顶层任务默认 nil
        let id2 = await coordinator.spawn(agent: MockAgent(), spec: .init(name: "top", task: "y"))
        let state2 = await coordinator.waitFor(id2)
        XCTAssertNil(state2.parentID)
    }

    func testOnFinishedCallbackFiresOnce() async throws {
        let box = FinishedBox()
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        coordinator.onFinished = { state in
            Task { await box.append(state) }
        }
        let id = await coordinator.spawn(agent: MockAgent(), spec: .init(name: "cb", task: "x"))
        let state = await coordinator.waitFor(id)
        // 等回调落盘
        try await Task.sleep(nanoseconds: 150_000_000)
        let fired = await box.states
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.id, id)
        XCTAssertEqual(fired.first?.phase, state.phase)
    }

    func testShutdownCancelsAllAndClears() async throws {
        let box = EventBox()
        let coordinator = SubagentCoordinator(maxConcurrent: 1, onEvent: { event in
            Task { await box.append(event) }
        })
        let blocker = MockAgent(delay: 0.2)
        let slow = MockAgent(delay: 10)
        let blockerID = await coordinator.spawn(agent: blocker, spec: .init(name: "blocker", task: "x"))
        let slowID = await coordinator.spawn(agent: slow, spec: .init(name: "slow", task: "x", timeout: 60))
        try await Task.sleep(nanoseconds: 150_000_000)
        await coordinator.shutdown()
        // shutdown 后协调器内条目清空（无僵尸残留）
        let all = await coordinator.allStates()
        XCTAssertTrue(all.isEmpty)
        // 运行中的 blocker 被取消
        let blockerCancel = await blocker.cancelCount
        XCTAssertEqual(blockerCancel, 1)
        // 排队的 slow 不启动、直接落 cancelled 终态（事件证据）
        try await Task.sleep(nanoseconds: 100_000_000)
        let events = await box.events
        let cancelledIDs = events.compactMap { event -> SubagentID? in
            if case let .finished(_, s) = event, s.phase == .cancelled {
                return s.id
            }
            return nil
        }
        XCTAssertTrue(cancelledIDs.contains(blockerID))
        XCTAssertTrue(cancelledIDs.contains(slowID))
    }

    func testAutoReclaimReapsExpiredFinished() async throws {
        let box = EventBox()
        let coordinator = SubagentCoordinator(maxConcurrent: 2, onEvent: { event in
            Task { await box.append(event) }
        })
        let idA = await coordinator.spawn(agent: MockAgent(), spec: .init(name: "A", task: "x"))
        let idB = await coordinator.spawn(agent: MockAgent(), spec: .init(name: "B", task: "x"))
        _ = await coordinator.waitForAll()
        await coordinator.startAutoReclaim(interval: .milliseconds(20), gracePeriod: 0.05)
        // 轮询直到回收完成（上限 3 秒）
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await (coordinator.allStates()).isEmpty {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let remaining = await coordinator.allStates()
        XCTAssertTrue(remaining.isEmpty, "终态条目超宽限期后应被回收")
        try await Task.sleep(nanoseconds: 100_000_000)
        let events = await box.events
        let reclaimed = events.compactMap { event -> SubagentID? in
            if case let .reclaimed(id) = event {
                return id
            }
            return nil
        }
        XCTAssertTrue(reclaimed.contains(idA))
        XCTAssertTrue(reclaimed.contains(idB))
        await coordinator.stopAutoReclaim()
    }

    func testReapSkipsNonExpired() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let id = await coordinator.spawn(agent: MockAgent(), spec: .init(name: "keep", task: "x"))
        _ = await coordinator.waitFor(id)
        let reclaimed = await coordinator.reap(gracePeriod: 3600)
        XCTAssertEqual(reclaimed, 0)
        let all = await coordinator.allStates()
        XCTAssertEqual(all.count, 1)
    }

    func testCountsByPhase() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let quick = MockAgent(delay: 0.02)
        let running = MockAgent(delay: 0.4)
        let queued = MockAgent(delay: 10)
        _ = await coordinator.spawn(agent: quick, spec: .init(name: "quick", task: "x"))
        let idR = await coordinator.spawn(agent: running, spec: .init(name: "running", task: "x", timeout: 60))
        let idS = await coordinator.spawn(agent: queued, spec: .init(name: "queued", task: "x", timeout: 60))
        // 轮询到目标分布：quick 已完成、running 运行中、queued 排队
        let deadline = Date().addingTimeInterval(3)
        var counts = await coordinator.counts()
        while Date() < deadline {
            if counts.running == 1, counts.queued == 1, counts.finished == 1 {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
            counts = await coordinator.counts()
        }
        XCTAssertEqual(counts.running, 1)
        XCTAssertEqual(counts.queued, 1)
        XCTAssertEqual(counts.finished, 1)
        // 清理未终态条目，避免残留任务
        await coordinator.cancel(idS)
        await coordinator.cancel(idR)
        _ = await coordinator.waitForAll()
    }
}
