import Agent
import Foundation
import LLM
import Session
@testable import Subagent
import Testing
import Tools

// MARK: - 覆盖审计轮 17：Subagent 残余兜底行（reaper 循环 / NO-STATE 缝 / 空槽位缝 / 排队兜底 / 历史损坏兜底 / 工具文本闭包）

/// 脚本化 LLM（同 SubagentTests 的 ScriptedTextLLM 模式；私有类型不可跨文件复用，此处本地定义）
private final class ScriptedTextLLMR17: LLMProvider, @unchecked Sendable {
    let id = "scripted-llm-r17"
    let supportedModels = ["mock-model"]
    private let responses: [LLMResponse]
    private let lock = NSLock()
    private var count = 0

    init(responses: [LLMResponse]) {
        self.responses = responses
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        var idx = 0
        lock.withLock {
            idx = min(count, max(responses.count - 1, 0))
            count += 1
        }
        return responses[idx]
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@Suite("Subagent R17 Gap Coverage")
struct SubagentR17GapTests {
    /// ① 自动回收：reaper Task 循环体（L241）+ 终态条目超宽限期被回收
    @Test("autoReclaim: reaper 循环回收终态条目")
    func autoReclaimReaperLoop() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let id = await coordinator.spawn(agent: MockAgent(), spec: .init(name: "quick", task: "x"))
        _ = await coordinator.waitFor(id) // 终态（succeeded，finishedAt 已落）
        await coordinator.startAutoReclaim(interval: .milliseconds(20), gracePeriod: 0)
        let deadline = Date().addingTimeInterval(3)
        var states = await coordinator.allStates()
        while !states.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            states = await coordinator.allStates()
        }
        await coordinator.stopAutoReclaim()
        #expect(states.isEmpty)
    }

    /// ② finalize 测试缝：未知 id → NO-STATE 防御分支（L330/331）+ stateNameFor 全函数
    @Test("finalize 缝: 未知 id → NO-STATE 分支")
    func finalizeNoState() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        await coordinator.finalize(SubagentID(), result: nil) // 不崩溃即通过
    }

    /// ③ releaseSlot 测试缝：空协调器 → guard-EMPTY 防御分支（L410/411）
    @Test("releaseSlot 缝: 空协调器 → guard-EMPTY 分支")
    func releaseSlotEmpty() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        await coordinator.releaseSlot() // 不崩溃即通过
    }

    /// ④ 单槽并发：排队任务 startedAt nil → `?? .distantFuture` 兜底；
    /// reap 过滤闭包；排队中取消 → cancelled；removeFinished 清理
    /// 轮 18 根因修复（flake 2/25 复现，slotLog 实锤）：spawn 仅入队 Task，A/B 的 run task
    /// 谁先落到协调器 actor 不确定——B 可先抢单槽跑满 10s、A 反排队 → reap 时双终态 reaped==2。
    /// 生产协调器行为正确（槽位上限/FIFO 转移/无泄漏均正常），flaky 的是测试对「先 spawn 先拿槽」
    /// 的假设。修复 = 等 A 确定 running（持槽）后再 spawn B，B 必然排队。
    @Test("单槽并发: 排队兜底 / reap 过滤闭包 / 排队取消")
    func queuedTaskGaps() async {
        let coordinator = SubagentCoordinator(maxConcurrent: 1)
        let idA = await coordinator.spawn(agent: MockAgent(delay: 0.2), spec: .init(name: "A", task: "x"))
        // 确定性持槽：A 先确定进入 running（持有唯一槽位）再 spawn B。
        // 窗口充足（A 持槽 0.2s ≫ 10ms 轮询），停滞期下若 A 未被观察到 running 则断言失败可诊断。
        let aRunning = await eventuallyRunning(coordinator, id: idA)
        #expect(aRunning)
        let idB = await coordinator.spawn(agent: MockAgent(delay: 10), spec: .init(name: "B", task: "y"))
        // 此刻 A 运行中、B 排队（startedAt nil）→ allStates 排序的 `?? .distantFuture` thunk
        let snap = await coordinator.allStates()
        #expect(snap.count == 2)
        #expect(snap.contains { $0.id == idB && $0.phase == .pending && $0.startedAt == nil })

        let stateA = await coordinator.waitFor(idA)
        #expect(stateA.phase == .succeeded)

        // reap：A 已终态 → 过滤闭包执行（gracePeriod 0 → 立即回收）。
        // B 此时已被唤醒进入 running（槽位转移），非终态 → 仅回收 A。
        let reaped = await coordinator.reap(gracePeriod: 0)
        #expect(reaped == 1)

        // 取消运行中的 B（槽位已转移）：cancel → send 循环感知 cancelCount 提前返回 → cancelled 终态。
        await coordinator.cancel(idB)
        let stateB = await coordinator.waitFor(idB)
        #expect(stateB.phase == .cancelled)
        let removed = await coordinator.removeFinished()
        #expect(removed == 1)
    }

    /// 有界轮询：等待指定子任务进入 running（替代固定 sleep，防事件循环调度抖动）
    private func eventuallyRunning(_ coordinator: SubagentCoordinator, id: SubagentID, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let states = await coordinator.allStates()
            if states.contains(where: { $0.id == id && $0.phase == .running }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    /// ⑤ 历史文件损坏 → 解码失败 `?? []` 兜底
    @Test("HistoryStore: 损坏文件 → 空数组兜底")
    func historyStoreCorruptedFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-subagent-r17-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("corrupt.json")
        try Data("definitely-not-json{{{".utf8).write(to: url)
        #expect(SubagentHistoryStore.load(url: url).isEmpty)
    }

    /// ⑥ spawn_subagent 成功路径：子 Agent 文本输出 → compactMap `return s` 闭包分支（L531）
    @Test("SpawnSubagentTool: 成功路径文本提取闭包")
    func spawnToolSuccessTextExtraction() async throws {
        let llm = ScriptedTextLLMR17(responses: [
            LLMResponse(model: "mock-model", content: [.text("R17 子任务文本输出")], finishReason: .stop),
        ])
        let coordinator = SubagentCoordinator(maxConcurrent: 2)
        let tool = SpawnSubagentTool(
            coordinator: coordinator,
            subTools: ToolRegistry(),
            model: "mock-model",
            makeLLM: { llm }
        )
        let context = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let result = try await tool.execute(["task": "计算答案", "name": "r17"], context: context)
        #expect(result.error == nil)
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        #expect(text.contains("R17 子任务文本输出"))
    }
}
