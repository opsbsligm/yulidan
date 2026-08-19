import Agent
import Foundation
import LLM
import ServiceContainer
import Session
import Tools

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
    /// 结构化入参（键值对，随任务文本一起下发给子 Agent）
    public var context: [String: String]
    /// 父任务标识（多 Agent 树展示用；nil = 顶层任务）
    public var parentID: SubagentID?

    public init(name: String, task: String, timeout: TimeInterval = 120,
                context: [String: String] = [:], parentID: SubagentID? = nil) {
        self.name = name
        self.task = task
        self.timeout = timeout
        self.context = context
        self.parentID = parentID
    }
}

// MARK: - 状态与事件

/// 子任务阶段
public enum SubagentPhase: String, Sendable, Codable, Hashable {
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

    /// 终态对应的系统通知标题（nil = 不发通知，如用户主动取消 / 非终态）
    public var notificationTitle: String? {
        switch self {
        case .succeeded: "子任务完成"
        case .failed: "子任务失败"
        case .timedOut: "子任务超时"
        case .cancelled, .pending, .running: nil
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
    /// 父任务标识（nil = 顶层任务）
    public var parentID: SubagentID?

    /// 执行耗时（仅终态有值）
    public var elapsed: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    public init(id: SubagentID, name: String, phase: SubagentPhase = .pending, timeout: TimeInterval = 0,
                parentID: SubagentID? = nil) {
        self.id = id
        self.name = name
        self.phase = phase
        self.timeout = timeout
        self.parentID = parentID
    }
}

/// 协调器事件（UI/日志观察用）
public enum SubagentEvent: Sendable {
    case spawned(id: SubagentID, name: String)
    case started(id: SubagentID)
    case finished(id: SubagentID, state: SubagentState)
    /// 终态条目超过宽限期，内存已回收（历史持久化不受影响）
    case reclaimed(id: SubagentID)
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

    /// 生命周期事件回调（init 可传入，也可在宿主成员就绪后赋值）
    public nonisolated(unsafe) var onEvent: (@Sendable (SubagentEvent) -> Void)?

    /// 完成回调（终态落定时触发；与 onEvent 独立，供通知/统计直挂）
    public nonisolated(unsafe) var onFinished: (@Sendable (SubagentState) -> Void)?

    private var states: [SubagentID: SubagentState] = [:]
    private var reaperTask: Task<Void, Never>?
    private var agents: [SubagentID: any Agent] = [:]
    private var tasks: [SubagentID: Task<Void, Never>] = [:]
    /// 已占用槽位数（含已转移给排队等待者、尚未唤醒自增的部分）
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
        states[id] = SubagentState(id: id, name: spec.name, timeout: spec.timeout, parentID: spec.parentID)
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
            release(id)
        }
        return finishedIDs.count
    }

    /// 运行概览（监控/调试用）
    public func counts() -> (running: Int, queued: Int, finished: Int) {
        var running = 0
        var queued = 0
        var finished = 0
        for state in states.values {
            switch state.phase {
            case .running: running += 1
            case .pending: queued += 1
            default: finished += 1
            }
        }
        slotLog("counts-read running=\(running) queued=\(queued) finished=\(finished) states=\(states.count)")
        return (running, queued, finished)
    }

    /// 启动自动回收：终态条目保留 gracePeriod 后释放内存（防僵尸 Agent 残留）
    ///
    /// 回收仅释放协调器内引用（AgentLoop 随之析构）；磁盘历史不受影响。
    public func startAutoReclaim(interval: Duration = .seconds(60), gracePeriod: TimeInterval = 600) {
        guard reaperTask == nil else { return }
        reaperTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await reap(gracePeriod: gracePeriod)
            }
        }
    }

    /// 停止自动回收
    public func stopAutoReclaim() {
        reaperTask?.cancel()
        reaperTask = nil
    }

    /// 立即回收一次超过宽限期的终态条目；返回回收数量
    @discardableResult
    public func reap(gracePeriod: TimeInterval) -> Int {
        let cutoff = Date().addingTimeInterval(-gracePeriod)
        let expired = states.filter { state in
            state.value.phase.isTerminal && (state.value.finishedAt ?? Date()) < cutoff
        }.map(\.key)
        for id in expired {
            release(id)
            onEvent?(.reclaimed(id: id))
        }
        return expired.count
    }

    /// 停止协调器：取消全部未终态子任务、等待落定并清空（宿主退出时调用，保证无僵尸 Agent）
    public func shutdown() async {
        stopAutoReclaim()
        for (id, state) in states where !state.phase.isTerminal {
            _ = cancelRequested.insert(id)
            if state.phase == .running {
                await agents[id]?.cancel(keepInbox: true)
            }
        }
        _ = await waitForAll()
        removeFinished()
    }

    // MARK: 内部

    /// 释放单个条目（状态/Agent/任务引用一并解除，AgentLoop 随之可析构）
    private func release(_ id: SubagentID) {
        states[id] = nil
        agents[id] = nil
        tasks[id] = nil
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

        await agent.send(UserMessage(content: [.text(Self.taskMessage(spec))]), target: .nextTurn, wakeup: true)
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
        slotLog("markRunning name=\(state.name)")
    }

    /// 落终态：补 finishedAt、唤醒等待者、释放并发槽位、发事件
    /// 阶段优先级：timedOut > cancelled > failed > succeeded
    private func finalize(_ id: SubagentID, result: AgentResult?) {
        guard var state = states[id] else {
            slotLog("finalize-NO-STATE name=\(stateNameFor(id))")
            return
        }
        slotLog("finalize-start name=\(state.name) phase=\(String(describing: state.phase)) timeout=\(timeoutRequested.contains(id)) cancel=\(cancelRequested.contains(id))")
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
        onFinished?(state)
    }

    /// 任务消息 = 任务文本 + 结构化入参（如有）
    private static func taskMessage(_ spec: SubagentSpec) -> String {
        guard !spec.context.isEmpty else { return spec.task }
        let lines = spec.context.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
        return spec.task + "\n\n【输入参数】\n" + lines.joined(separator: "\n")
    }

    private func stateNameFor(_ id: SubagentID) -> String {
        states[id]?.name ?? "?"
    }

    /// 槽位门控诊断日志（env `SUBAGENT_SLOT_DEBUG=1` 开启；默认零开销）。
    /// 用途：macOS 27 beta 调度停滞窗口内捕获槽位/状态时间线（QUALITY_REPORT P1 现场取证）。
    private func slotLog(_ msg: String) {
        guard ProcessInfo.processInfo.environment["SUBAGENT_SLOT_DEBUG"] != nil else { return }
        let text = "[slot] t=\(Date().timeIntervalSince1970) \(msg)\n"
        FileHandle.standardError.write(text.data(using: .utf8) ?? Data())
    }

    private func acquireSlot() async {
        if runningCount < maxConcurrent {
            runningCount += 1
            slotLog("fast-acquire count=\(runningCount)")
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            slotWaiters.append(continuation)
        }
        // 排队唤醒：槽位已由释放方直接转移（runningCount 不变），不得重复计数
        slotLog("waiter-woken count=\(runningCount)")
    }

    /// 释放并发槽位
    ///
    /// 若有排队等待者，槽位**直接转移**给队首等待者（`runningCount` 不变、唤醒之）；
    /// 无等待者才递减。
    ///
    /// ⚠️ 若「先递减、再唤醒」，在 `runningCount` 回落到 0 与等待者唤醒自增之间存在
    /// 空窗：此时新任务的快速路径会抢占幽灵槽位，叠加等待者自增后并发数将超过
    /// `maxConcurrent`（作业调度顺序反转时必现，macOS 27 beta 调度停滞曾暴露此竞态）。
    private func releaseSlot() {
        if !slotWaiters.isEmpty {
            slotLog("release-transfer waiters=\(slotWaiters.count) count=\(runningCount)")
            slotWaiters.removeFirst().resume()
            return
        }
        guard runningCount > 0 else {
            slotLog("release-guard-EMPTY count=\(runningCount)")
            return
        }
        runningCount -= 1
        slotLog("release-decrement count=\(runningCount)")
    }
}

// MARK: - 历史持久化

/// 子任务历史记录（磁盘 JSON 存储；App 重启后展示终态子任务）
public struct SubagentHistoryItem: Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let phase: SubagentPhase
    public let resultText: String?
    public let error: String?
    public let elapsed: TimeInterval?
    public let stepLines: [String]
    public let finishedAt: Date

    public init(id: String, name: String, phase: SubagentPhase, resultText: String?,
                error: String?, elapsed: TimeInterval?, stepLines: [String], finishedAt: Date) {
        self.id = id
        self.name = name
        self.phase = phase
        self.resultText = resultText
        self.error = error
        self.elapsed = elapsed
        self.stepLines = stepLines
        self.finishedAt = finishedAt
    }
}

/// 历史文件读写（JSON 数组；最新在前；带数量上限）
public enum SubagentHistoryStore {
    public static let defaultCap = 50

    /// 读取历史；文件不存在 / 损坏时返回空
    public static func load(url: URL) -> [SubagentHistoryItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SubagentHistoryItem].self, from: data)) ?? []
    }

    /// 保存历史（截取前 cap 条，原子写入；失败静默）
    public static func save(_ items: [SubagentHistoryItem], url: URL, cap: Int = defaultCap) {
        let trimmed = Array(items.prefix(cap))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - spawn_subagent 工具（主 Agent 委派子任务）

/// 子任务 LLM 工厂（宿主提供；App 用当前模型配置，无 Key 时返回 nil）
public typealias SubagentLLMFactory = @Sendable () async -> (any LLMProvider)?

/// spawn_subagent 工具：主 Agent 可委派子任务并等待其结果
///
/// 子 Agent 使用独立 AgentLoop 与子工具注册表（不含本工具，防止递归派生）。
/// 超时/失败返回错误结果（不 throw），让主 Agent 自行降级决策。
public struct SpawnSubagentTool: Tool, Sendable {
    public let name = "spawn_subagent"
    public let description = "委派一个子任务给子 Agent 执行并等待结果（独立上下文、共享内置工具，可并行使用多次）"
    public let parameterSchema = """
    {"type":"object","properties":{"task":{"type":"string","description":"子任务完整描述"},
     "name":{"type":"string","description":"子任务名称（展示用）"},
     "timeout":{"type":"number","description":"超时秒数，默认 120"}},"required":["task"]}
    """
    public let requiredParameters = ["task"]

    private let coordinator: SubagentCoordinator
    private let subTools: ToolRegistry
    private let model: String
    private let systemPrompt: String?
    private let maxSteps: Int
    private let makeLLM: SubagentLLMFactory

    public init(
        coordinator: SubagentCoordinator,
        subTools: ToolRegistry,
        model: String,
        systemPrompt: String? = nil,
        maxSteps: Int = 8,
        makeLLM: @escaping SubagentLLMFactory
    ) {
        self.coordinator = coordinator
        self.subTools = subTools
        self.model = model
        self.systemPrompt = systemPrompt
        self.maxSteps = maxSteps
        self.makeLLM = makeLLM
    }

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        let task = (args["task"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else {
            return ToolResult(content: [.text("缺少必填参数 task")],
                              error: ToolError(name: name, code: "invalid_args", message: "缺少必填参数 task"))
        }
        let rawName = args["name"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let name = rawName.isEmpty ? "子任务" : rawName
        let timeout = args["timeout"].flatMap(Double.init) ?? 120
        guard let llm = await makeLLM() else {
            return ToolResult(content: [.text("模型未配置（缺 API Key），无法派生子任务")],
                              error: ToolError(name: name, code: "no_llm", message: "模型未配置"))
        }
        let agent = AgentLoop(
            sessionID: context.sessionID, llm: llm, tools: subTools,
            model: model, systemPrompt: systemPrompt, maxSteps: maxSteps
        )
        let id = await coordinator.spawn(agent: agent, spec: SubagentSpec(name: name, task: task, timeout: timeout))
        let state = await coordinator.waitFor(id)
        switch state.phase {
        case .succeeded:
            var text = ""
            if let blocks = state.result?.messages.first?.content {
                text = blocks.compactMap { block -> String? in
                    if case let .text(s) = block {
                        return s
                    }
                    return nil
                }.joined()
            }
            return ToolResult(content: [.text(text.isEmpty ? "子任务完成（无文本输出）" : text)])
        default:
            let detail = state.error ?? "未知错误"
            return ToolResult(content: [.text("子任务\(state.phase.rawValue)：\(detail)")],
                              error: ToolError(name: name, code: state.phase.rawValue, message: detail))
        }
    }
}
