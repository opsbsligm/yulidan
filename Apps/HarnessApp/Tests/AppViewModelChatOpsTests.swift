import Foundation
@testable import HarnessApp
import LLM
import Session
import Subagent
import Testing

// MARK: - AppViewModel 会话操作（场景测试：clearChat 清空持久化 / retryLastMessage 失败重试 / spawnSubagent 入口 / 插件启停）

/// 失败一次后成功的 LLM（retryLastMessage 场景）
private final class FailOnceProvider: LLMProvider, @unchecked Sendable {
    struct SimulatedNetworkError: LocalizedError {
        var errorDescription: String? {
            "模拟网络超时"
        }
    }

    let id = "fail-once"
    let supportedModels = ["test-model"]
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.withLock { count }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        lock.withLock { count += 1 }
        if count == 1 {
            throw SimulatedNetworkError()
        }
        return LLMResponse(model: "test-model", content: [.text("重试成功")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// 脚本化子 Agent LLM（纯文本收敛）
private final class ScriptedSubagentProvider: LLMProvider, @unchecked Sendable {
    let id = "scripted-subagent"
    let supportedModels = ["test-model"]

    func request(_: LLMRequest) async throws -> LLMResponse {
        LLMResponse(model: "test-model", content: [.text("子任务完成：已核验 42")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
@Suite("AppViewModel 会话操作", .serialized)
struct AppViewModelChatOpsTests {
    init() {
        // 只重置通知工厂；provider 走实例缝（不触碰静态工厂，防跨 suite 互踩）
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-chatops-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-chatops-skills-\(UUID().uuidString)")
    }

    // MARK: 场景 1：clearChat（消息 + DB 事件清空，currentTurn 保留）

    @Test("clearChat：UI 消息清空 + DB 事件异步清空 + currentTurn 保留")
    func clearChatClearsMessagesAndDB() async {
        let provider = PlainTextProvider()
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        vm.createNewSession()
        guard let s1 = vm.selectedSession else {
            Issue.record("会话未选中"); return
        }
        vm.sendMessage("待清空的消息")
        let d0 = Date().addingTimeInterval(15)
        while Date() < d0 {
            if !vm.isGenerating, vm.messages.last?.role == .assistant,
               vm.messages.last?.status == .delivered {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.messages.count == 2)
        #expect(vm.selectedSession?.currentTurn == 1)

        // 清空
        vm.clearChat()
        #expect(vm.messages.isEmpty)
        #expect(vm.generationError == nil)
        #expect(vm.selectedSession?.currentTurn == 1) // 轮次计数保留

        // DB 事件异步清空
        if let db = try? SessionDB(dbURL: dbURL) {
            let d1 = Date().addingTimeInterval(10)
            while Date() < d1 {
                let rec = try? await db.load(s1.id)
                if rec?.events.isEmpty == true {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            let rec = try? await db.load(s1.id)
            #expect(rec?.events.isEmpty == true)
            #expect(rec?.currentTurn == 1)
        } else {
            Issue.record("测试 DB 打开失败")
        }
    }

    // MARK: 场景 2：retryLastMessage（失败 → 重试成功；错误消息移除；空态 no-op）

    @Test("retryLastMessage：失败后重试成功（错误消息移除）+ 空态 no-op")
    func retryLastMessageRecovers() async {
        let provider = FailOnceProvider()
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        // 首轮失败：错误助手消息 + generationError
        vm.sendMessage("需要重试的问题")
        let d0 = Date().addingTimeInterval(15)
        while Date() < d0 {
            if !vm.isGenerating, vm.messages.last?.status == .error {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.messages.last?.status == .error)
        #expect(vm.generationError != nil)

        // 重试：错误消息移除 + 重发最后用户消息 + 收敛成功
        vm.retryLastMessage()
        let d1 = Date().addingTimeInterval(15)
        while Date() < d1 {
            if !vm.isGenerating, vm.messages.last?.role == .assistant,
               vm.messages.last?.status == .delivered {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.messages.last?.content == "重试成功")
        #expect(vm.messages.contains(where: { $0.status == .error }) == false) // 错误消息已移除
        #expect(vm.generationError == nil)
        #expect(provider.requestCount == 2)
        // 消息流：首轮 user + 重试 user + 助手
        #expect(vm.messages.filter { $0.role == .user }.count == 2)

        // 空态 no-op：lastUserMessage 为空时不发起请求
        let dbURL2 = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL2) }
        let vm2 = AppViewModel(skillUserDirectory: tempSkillDir(), sessionDBURL: dbURL2)
        try? await Task.sleep(for: .milliseconds(300)) // 等启动加载窗口（空 DB）
        vm2.retryLastMessage()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(vm2.messages.isEmpty)
        #expect(vm2.sessions.isEmpty)
    }

    // MARK: 场景 3：spawnSubagent VM 入口（脚本化 LLM 真实执行到终态）

    @Test("spawnSubagent 入口：空名 no-op + 脚本化 LLM 子任务执行到 succeeded + 结果回传")
    func spawnSubagentEntry() async {
        let provider = ScriptedSubagentProvider()
        // 子任务历史文件隔离（防跨 run 累积：终态条目会写入历史，下次 init 加载）
        let historyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-chatops-history-\(UUID().uuidString).json")
        AppViewModel.subagentHistoryURLOverride = historyURL
        defer {
            AppViewModel.subagentHistoryURLOverride = nil
            try? FileManager.default.removeItem(at: historyURL)
        }
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        // 空名/空任务 guard：不派生（断言列表计数不变，鲁棒于历史加载态）
        let beforeCount = vm.subagents.count
        vm.spawnSubagent(name: "   ", task: "任务", timeout: 10)
        try? await Task.sleep(for: .milliseconds(300))
        await vm.refreshSubagents()
        #expect(vm.subagents.count == beforeCount)

        // 真实派生：脚本化 LLM 完成子任务 → 终态 succeeded + 结果文本
        let spawnStart = Date()
        vm.spawnSubagent(name: "核验任务", task: "完成核验", timeout: 30)
        let deadline = Date().addingTimeInterval(15)
        var item: SubagentDisplayItem?
        while Date() < deadline {
            await vm.refreshSubagents()
            // finishedAt 晚于派生时刻：排除历史残留同名片段
            if let found = vm.subagents.first(where: {
                $0.name == "核验任务" && ($0.finishedAt ?? .distantPast) >= spawnStart
            }), found.phase == .succeeded || found.phase == .failed {
                item = found
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(item != nil)
        #expect(item?.phase == .succeeded)
        #expect(item?.resultText?.contains("子任务完成：已核验 42") == true)
    }

    // MARK: 场景 4：插件启停（真实 PluginManager 安装/卸载循环）

    @Test("togglePlugin：内置插件停用（卸载出列表）→ 再启用（重新安装激活）")
    func togglePluginCycle() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)

        // 等待 init 自动安装内置插件完成（terminal 插件激活在列）
        let d0 = Date().addingTimeInterval(15)
        while Date() < d0 {
            await vm.refreshPlugins()
            if vm.plugins.contains(where: { $0.id == "terminal" && $0.isActive }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let active = vm.plugins.first(where: { $0.id == "terminal" }), active.isActive else {
            Issue.record("terminal 内置插件未安装激活"); return
        }

        // 停用：uninstall → 列表移除
        vm.togglePlugin(active)
        let d1 = Date().addingTimeInterval(15)
        while Date() < d1 {
            await vm.refreshPlugins()
            if vm.plugins.contains(where: { $0.id == "terminal" }) == false {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.plugins.contains(where: { $0.id == "terminal" }) == false)

        // 再启用：makeBuiltInPlugin + install → 重新激活
        let inactive = PluginDisplayItem(
            id: "terminal", name: "终端", version: "0.1.0",
            state: .stopped, isActive: false, permissions: [],
            author: nil, description: "内置终端插件"
        )
        vm.togglePlugin(inactive)
        let d2 = Date().addingTimeInterval(15)
        while Date() < d2 {
            await vm.refreshPlugins()
            if vm.plugins.contains(where: { $0.id == "terminal" && $0.isActive }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.plugins.contains(where: { $0.id == "terminal" && $0.isActive }))
    }
}
