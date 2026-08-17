import Agent
import Foundation
import ServiceContainer
import Session

// MARK: - 标识

/// 子任务唯一标识
public struct SubagentID: Sendable, Hashable, Codable {
    public let rawValue: UUID
    public init() {
        rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

// MARK: - 任务规格

/// 子任务定义：交给某个 Agent 执行的一段任务
public struct SubagentSpec: Sendable {
    /// 展示名（日志/UI）
    public var name: String
    /// 任务文本（作为 UserMessage 发给子 Agent）
    public var task: String
    /// 单任务超时（秒）：到点后取消子 Agent 并标记 timedOut
    public var timeout: TimeInterval

    public init(name: String, task: String, timeout: TimeInterval = 120) {
        self.name = name
        self.task = task
        self.timeout = timeout
    }
}

// MARK: - 状态与事件

/// 子任务阶段
public enum SubagentPhase: String, Sendable {
    case pending // 排队等待并发槽位
    case running
    case succeeded
    case failed
    case timedOut
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .timedOut, .cancelled:
            true
        case .pending, .running:
            false
        }
    }
}

/// 子任务可观察状态
public struct SubagentState: Sendable {
    public let id: SubagentID
    public let name: String
    public var phase: SubagentPhase
    public var result: AgentResult?
    public var error: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var timeout: TimeInterval

    /// 执行耗时（仅终态有值）
    public var elapsed: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    public init(id: SubagentID, name: String, phase: SubagentPhase = .pending, timeout: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.phase = phase
        self.timeout = timeout
    }
}

/// 协调器事件（UI/日志观察用）
public enum SubagentEvent: Sendable {
    case spawned(id: SubagentID, name: String)
    case started(id: SubagentID)
    case finished(id: SubagentID, state: SubagentState)
}

// MARK: - 协调器

/// 多 Agent 协调器
///
/// 职责：把多个子任务分发到多个 Agent 上并行执行，提供
/// 并发上限（maxConcurrent）、单任务超时、取消、等待与事件通知。
///
/// 用法：
/// ```swift
/// let coordinator = SubagentCoordinator(maxConcurrent: 2)
/// let id = await coordinator.spawn(agent: worker, spec: .init(name: "摘要", task: "…"))
/// let state = await coordinator.waitFor(id)
/// ```
public actor SubagentCoordinator {
    public let maxConcurrent: Int

    private let onEvent: (@Sendable (SubagentEvent) -> Void)?

    private var states: [SubagentID: SubagentState] = [:]
    private var agents: [SubagentID: any Agent] = [:]
    private var tasks: [SubagentID: Task<Void, Never>] = [:]
    private var runningCount = 0
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []
    private var stateWaiters: [SubagentID: [CheckedContinuation<SubagentState, Never>]] = [:]
    // 终态统一在 finalize 落定；这里只记录“请求”，避免 waitFor 提前返回中间快照
    private var cancelRequested: Set<SubagentID> = []
    private var timeoutRequested: Set<SubagentID> = []

    /// - Parameter maxConcurrent: 同时 running 的子任务数上限（≥1）
    /// - Parameter onEvent: 生命周期事件回调（在协调器 actor 上触发）
    public init(maxConcurrent: Int = 4, onEvent: (@Sendable (SubagentEvent) -> Void)? = nil) {
        precondition(maxConcurrent >= 1, "maxConcurrent 必须 >= 1")
        self.maxConcurrent = maxConcurrent
        self.onEvent = onEvent
    }

    // MARK: 生命周期

    /// 派生一个子任务（非阻塞）；排队等待并发槽位后立即返回
    @discardableResult
    public func spawn(agent: some Agent, spec: SubagentSpec) -> SubagentID {
        let id = SubagentID()
        states[id] = SubagentState(id: id, name: spec.name, timeout: spec.timeout)
        agents[id] = agent
        onEvent?(.spawned(id: id, name: spec.name))
        tasks[id] = Task { [weak self] in
            await self?.run(id: id, agent: agent, spec: spec)
        }
        return id
    }

    /// 取消指定子任务（幂等；排队中或运行中均可取消）
    public func cancel(_ id: SubagentID) async {
        guard let state = states[id], !state.phase.isTerminal else { return }
        _ = cancelRequested.insert(id)
        await agents[id]?.cancel(keepInbox: true)
    }

    /// 等待指定子任务到达终态
    public func waitFor(_ id: SubagentID) async -> SubagentState {
        precondition(states[id] != nil, "waitFor: 未知子任务 \(id)")
        if let state = states[id], state.phase.isTerminal {
            return state
        }
        return await withCheckedContinuation { continuation in
            stateWaiters[id, default: []].append(continuation)
        }
    }

    /// 等待所有已派生子任务到达终态
    public func waitForAll() async -> [SubagentState] {
        for (id, state) in states where !state.phase.isTerminal {
            _ = await waitFor(id)
        }
        return states.values.sorted { $0.startedAt ?? .distantFuture < $1.startedAt ?? .distantFuture }
    }

    /// 当前全部子任务状态快照
    public func allStates() -> [SubagentState] {
        states.values.sorted { $0.startedAt ?? .distantFuture < $1.startedAt ?? .distantFuture }
    }

    /// 移除已到终态的条目（UI 清理列表用）；返回移除数量
    @discardableResult
    public func removeFinished() -> Int {
        let finishedIDs = states.filter(\.value.phase.isTerminal).map(\.key)
        for id in finishedIDs {
            states[id] = nil
            agents[id] = nil
            tasks[id] = nil
        }
        return finishedIDs.count
    }

    // MARK: 内部

    private func run(id: SubagentID, agent: some Agent, spec: SubagentSpec) async {
        await acquireSlot()
        // 排队期间被取消：不执行，直接落终态并释放槽位
        guard !cancelRequested.contains(id) else {
            finalize(id, result: nil)
            return
        }
        markRunning(id)
        onEvent?(.started(id: id))

        let deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(spec.timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.handleTimeout(id: id)
        }
        defer { deadline.cancel() }

        await agent.send(UserMessage(content: [.text(spec.task)]), target: .nextTurn, wakeup: true)
        let result = await agent.whenIdle()
        finalize(id, result: result)
    }

    private func handleTimeout(id: SubagentID) {
        guard let state = states[id], !state.phase.isTerminal else { return }
        _ = timeoutRequested.insert(id)
        Task { [weak self] in
            await self?.agents[id]?.cancel(keepInbox: true)
        }
    }

    private func markRunning(_ id: SubagentID) {
        guard var state = states[id] else { return }
        state.phase = .running
        state.startedAt = Date()
        states[id] = state
    }

    /// 落终态：补 finishedAt、唤醒等待者、释放并发槽位、发事件
    /// 阶段优先级：timedOut > cancelled > failed > succeeded
    private func finalize(_ id: SubagentID, result: AgentResult?) {
        guard var state = states[id] else { return }
        if !state.phase.isTerminal {
            if timeoutRequested.contains(id) {
                state.phase = .timedOut
                state.error = "超过 \(Int(state.timeout.rounded(.up)))s 未响应"
            } else if cancelRequested.contains(id) {
                state.phase = .cancelled
                state.error = "已取消"
            } else if let error = result?.error {
                state.phase = .failed
                state.error = error
            } else {
                state.phase = .succeeded
            }
        }
        state.result = result
        state.finishedAt = Date()
        states[id] = state
        cancelRequested.remove(id)
        timeoutRequested.remove(id)
        releaseSlot()
        if let waiters = stateWaiters.removeValue(forKey: id) {
            for waiter in waiters {
                waiter.resume(returning: state)
            }
        }
        onEvent?(.finished(id: id, state: state))
    }

    private func acquireSlot() async {
        if runningCount < maxConcurrent {
            runningCount += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            slotWaiters.append(continuation)
        }
        runningCount += 1
    }

    private func releaseSlot() {
        runningCount -= 1
        if !slotWaiters.isEmpty {
            slotWaiters.removeFirst().resume()
        }
    }
}
