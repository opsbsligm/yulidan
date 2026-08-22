import Agent
import Foundation
@testable import HarnessApp
import LLM
import Notifications
import Session
import Subagent
import Testing
import Tools

/// 静默通知服务（测试进程无 bundle 身份，UNUserNotificationCenter 不可用）
final class NoopNotificationService: NotificationService, @unchecked Sendable {
    func requestAuthorization() async -> Bool {
        true
    }

    func post(title _: String, body _: String?, identifier _: String?) {}
}

// MARK: - 测试辅助

/// 脚本化文本 LLM（App 层测试专用；与包层测试同模式）
private final class ScriptedTextProvider: LLMProvider, @unchecked Sendable {
    let id = "app-test-llm"
    let supportedModels = ["mock-model"]
    private let text: String
    private let delay: TimeInterval
    private let lock = NSLock()
    private var count = 0

    init(text: String, delay: TimeInterval) {
        self.text = text
        self.delay = delay
    }

    var callCount: Int {
        lock.withLock { count }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        lock.withLock { count += 1 }
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        return LLMResponse(model: "mock-model", content: [.text(text)], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

func makeTestAgentLoop(text: String, delay: TimeInterval = 0.02) -> AgentLoop {
    AgentLoop(
        sessionID: SessionID(),
        llm: ScriptedTextProvider(text: text, delay: delay),
        tools: ToolRegistry(),
        model: "mock-model"
    )
}

// MARK: - stepLines 格式化

@Suite("SubagentDisplayItem.stepLines 格式化")
struct StepLinesFormatTests {
    @Test("工具调用 + 文本回复混合时间线")
    func mixed() {
        let call = Session.ContentBlock.toolCall(.init(id: "c1", name: "exec_command", arguments: #"{"cmd":"echo hi"}"#))
        let steps = [
            AssistantMessage(turn: 1, step: 1, content: [call], provider: "t", model: "m"),
            AssistantMessage(turn: 1, step: 2, content: [.text("执行完毕")], provider: "t", model: "m"),
        ]
        let lines = SubagentDisplayItem.stepLines(from: steps)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("步骤1 · 工具调用 exec_command"))
        #expect(lines[0].contains("echo hi"))
        #expect(lines[1].hasPrefix("步骤2 · 回复 执行完毕"))
    }

    @Test("空步骤返回空数组；纯工具调用无文本")
    func edge() {
        #expect(SubagentDisplayItem.stepLines(from: []).isEmpty)
        let lines = SubagentDisplayItem.stepLines(from: [
            AssistantMessage(turn: 1, step: 1, content: [.toolCall(.init(id: "x", name: "read_file", arguments: "{}"))], provider: "t", model: "m"),
        ])
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("步骤1 · 工具调用 read_file"))
    }
}

// MARK: - AppViewModel 多 Agent 协作（真实协调器 + 脚本化 LLM）

@MainActor
@Suite("AppViewModel 多 Agent 协作（真实协调器 + 脚本化 LLM）", .serialized)
struct AppViewModelSubagentTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    /// 每个用例独立的临时历史文件
    private func freshOverrideURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-app-test-\(UUID().uuidString).json")
    }

    /// 轮询 refresh 直到目标子任务满足条件（terminal=false 时等到 .running，避免首帧 pending 竞态）
    private func waitFor(_ vm: AppViewModel, id: String, terminal: Bool = true,
                         timeout: TimeInterval = 6) async -> SubagentDisplayItem? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: SubagentDisplayItem?
        while Date() < deadline {
            await vm.refreshSubagents()
            if let item = vm.subagents.first(where: { $0.id == id }) {
                last = item
                let satisfied = terminal ? item.phase.isTerminal : (item.phase == .running)
                if satisfied {
                    return item
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return last
    }

    @Test("refreshSubagents：新终态写入历史文件并合并进列表")
    func refreshMergesAndPersists() async {
        let url = freshOverrideURL()
        let vm = AppViewModel(subagentHistoryURLOverride: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let id = await vm.subagentCoordinator.spawn(agent: makeTestAgentLoop(text: "单测完成"), spec: .init(name: "单测任务", task: "完成任务"))
        let item = await waitFor(vm, id: id.rawValue.uuidString)
        #expect(item?.phase == .succeeded)
        #expect(item?.resultText?.contains("单测完成") == true)
        #expect(item?.stepLines.count == 1)
        let history = SubagentHistoryStore.load(url: url)
        #expect(history.count == 1)
        #expect(history.first?.name == "单测任务")
    }

    @Test("重复 refresh 不重复写历史（幂等去重）")
    func refreshIdempotent() async {
        let url = freshOverrideURL()
        let vm = AppViewModel(subagentHistoryURLOverride: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let id = await vm.subagentCoordinator.spawn(agent: makeTestAgentLoop(text: "幂等"), spec: .init(name: "幂等任务", task: "t"))
        _ = await waitFor(vm, id: id.rawValue.uuidString)
        await vm.refreshSubagents()
        await vm.refreshSubagents()
        #expect(SubagentHistoryStore.load(url: url).count == 1)
        #expect(vm.subagents.count == 1)
    }

    @Test("启动默认列表 = 磁盘历史（重启恢复）")
    func startupLoadsHistory() {
        let url = freshOverrideURL()
        SubagentHistoryStore.save([
            SubagentHistoryItem(id: "hist-1", name: "历史任务", phase: .succeeded, resultText: "历史结果",
                                error: nil, elapsed: 1.5, stepLines: ["步骤1 · 回复 历史结果"], finishedAt: Date()),
        ], url: url)
        let vm = AppViewModel(subagentHistoryURLOverride: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(vm.subagents.count == 1)
        #expect(vm.subagents.first?.name == "历史任务")
        #expect(vm.subagents.first?.phase == .succeeded)
    }

    @Test("clearFinishedSubagents：协调器与历史文件一并清空")
    func clearFinished() async {
        let url = freshOverrideURL()
        let vm = AppViewModel(subagentHistoryURLOverride: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let id = await vm.subagentCoordinator.spawn(agent: makeTestAgentLoop(text: "将被清理"), spec: .init(name: "清理任务", task: "t"))
        _ = await waitFor(vm, id: id.rawValue.uuidString)
        #expect(vm.subagents.count == 1)
        vm.clearFinishedSubagents()
        try? await Task.sleep(for: .milliseconds(200))
        await vm.refreshSubagents()
        #expect(vm.subagents.isEmpty)
        #expect(SubagentHistoryStore.load(url: url).isEmpty)
    }

    @Test("cancelSubagent：运行中的子任务被取消")
    func cancelRunning() async {
        let url = freshOverrideURL()
        let vm = AppViewModel(subagentHistoryURLOverride: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let id = await vm.subagentCoordinator.spawn(agent: makeTestAgentLoop(text: "很慢", delay: 3), spec: .init(name: "取消任务", task: "t"))
        // 等到运行中
        let running = await waitFor(vm, id: id.rawValue.uuidString, terminal: false, timeout: 3)
        #expect(running != nil)
        #expect(running?.phase == .running)
        guard let item = running else { return }
        vm.cancelSubagent(item)
        let final = await waitFor(vm, id: item.id)
        #expect(final?.phase == .cancelled)
        // 用户主动取消不写历史（notificationTitle 为 nil 但历史仍记录终态——按设计历史记录全部终态）
        #expect(SubagentHistoryStore.load(url: url).first?.phase == .cancelled)
    }

    @Test("spawnSubagentFromChat：无输入 → toast 拦截")
    func spawnFromChatValidation() {
        let url = freshOverrideURL()
        let vm = AppViewModel(subagentHistoryURLOverride: url)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.lastUserMessage = ""
        vm.spawnSubagentFromChat("   ")
        #expect(vm.toastMessage == "没有可派生的输入内容")
        #expect(vm.subagents.isEmpty)
    }
}
