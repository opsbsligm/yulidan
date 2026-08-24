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
        defer { try? FileManager.default.removeItem(at: historyURL) }
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL,
                              subagentHistoryURLOverride: historyURL)
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

    // MARK: 场景 4：模型切换即时生效（ModelSwitcherMenu 真实 UI 路径：save → 通知 → 主线程重载）

    @Test("模型切换即时生效：同提供商换模型复用循环，下轮 wire 立即使用新模型")
    func modelSwitchReusesLoop() async {
        let fx = ModelSwitchFixture(model: "model-A")
        defer { fx.tearDown() }
        fx.wireProvider()
        #expect(fx.vm.llmConfig.modelName == "model-A") // init 从磁盘加载

        fx.vm.createNewSession()
        fx.vm.sendMessage("第一轮")
        #expect(await waitDelivery(fx.vm))
        #expect(fx.provider.wireModels == ["model-A"])
        #expect(fx.vm.cachedLoopCountForTesting == 1)

        // 仅模型切换（同提供商/同端点）→ 通知重载；循环指纹不变 → 复用
        var cfg = fx.vm.llmConfig
        cfg.modelName = "model-B"
        cfg.save()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, fx.vm.llmConfig.modelName != "model-B" {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(fx.vm.llmConfig.modelName == "model-B")

        fx.vm.sendMessage("第二轮")
        #expect(await waitDelivery(fx.vm))
        #expect(fx.provider.wireModels == ["model-A", "model-B"]) // wire 立即使用新模型
        #expect(fx.vm.cachedLoopCountForTesting == 1) // 循环复用（历史保留），未重建
    }

    @Test("模型切换即时生效：端点切换（provider 级）重建循环，工厂重注入新配置")
    func modelSwitchRebuildsLoopOnEndpointChange() async {
        let fx = ModelSwitchFixture(model: "model-A")
        defer { fx.tearDown() }
        fx.wireProvider()

        fx.vm.createNewSession()
        fx.vm.sendMessage("第一轮")
        #expect(await waitDelivery(fx.vm))
        #expect(fx.factoryProbe.configs.count == 1)

        // 本地端点切换 → 上下文指纹变化 → 循环重建 → 工厂再次注入
        var cfg = fx.vm.llmConfig
        cfg.localBaseURL = "http://localhost:11500/v1"
        cfg.save()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, fx.vm.llmConfig.localBaseURL != "http://localhost:11500/v1" {
            try? await Task.sleep(for: .milliseconds(20))
        }

        fx.vm.sendMessage("第二轮")
        #expect(await waitDelivery(fx.vm))
        let configs = fx.factoryProbe.configs
        #expect(configs.count == 2) // 工厂二次注入 = 旧循环释放、新循环创建
        #expect(configs.last?.model == "model-A")
        #expect(configs.last?.baseURL == "http://localhost:11500/v1")
        #expect(fx.vm.cachedLoopCountForTesting == 1) // 新旧循环同 key 替换，缓存数稳定
    }
}

/// 等待生成收敛（末条助手消息 delivered）
@MainActor
private func waitDelivery(_ vm: AppViewModel) async -> Bool {
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
        if !vm.isGenerating, let last = vm.messages.last,
           last.role == .assistant, last.status == .delivered {
            return true
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return false
}

/// 模型切换测试夹具：独立 DB/技能目录 + llmConfig 磁盘快照（UserDefaults.standard 进程内共享，
/// 快照/还原防跨 suite 污染，同 ThemePlugin activeKey 纪律）
@MainActor
private final class ModelSwitchFixture {
    let vm: AppViewModel
    let provider: ModelSwitchProbeProvider
    let factoryProbe: FactoryConfigProbe
    private let dbURL: URL
    private let skillDir: URL
    private let originalConfigData: Data?

    init(model: String) {
        provider = ModelSwitchProbeProvider()
        factoryProbe = FactoryConfigProbe()
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-modelswitch-\(UUID().uuidString).sqlite")
        skillDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-modelswitch-skills-\(UUID().uuidString)")
        originalConfigData = UserDefaults.standard.data(forKey: "llmConfig")
        var cfg = LLMConfig.makeDefault()
        cfg.provider = .local
        cfg.modelName = model
        cfg.save()
        vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
    }

    /// 工厂注入探针（记录每次注入的配置快照 + 统一返回脚本化 provider）
    func wireProvider() {
        vm.providerFactoryOverride = { [factoryProbe, provider] (cfg: LLMConfig, _) -> any LLMProvider in
            factoryProbe.record(cfg)
            return provider
        }
    }

    func tearDown() {
        vm.providerFactoryOverride = nil
        if let originalConfigData {
            UserDefaults.standard.set(originalConfigData, forKey: "llmConfig")
        } else {
            UserDefaults.standard.removeObject(forKey: "llmConfig")
        }
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: skillDir)
    }
}

/// 记录每次 wire 请求的模型名（模型切换即时生效验证）
private final class ModelSwitchProbeProvider: LLMProvider, @unchecked Sendable {
    let id = "model-switch-probe"
    let supportedModels = ["probe"]
    private let lock = NSLock()
    private var recordedModels: [String] = []

    var wireModels: [String] {
        lock.withLock { recordedModels }
    }

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        lock.withLock { recordedModels.append(request.model) }
        return LLMResponse(model: request.model, content: [.text("OK")], finishReason: .stop)
    }

    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { recordedModels.append(request.model) }
            continuation.finish()
        }
    }
}

/// 记录工厂注入时的配置快照（重建路径验证：端点变化 → 工厂再次被调用）
private final class FactoryConfigProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(model: String, baseURL: String)] = []

    var configs: [(model: String, baseURL: String)] {
        lock.withLock { recorded }
    }

    func record(_ cfg: LLMConfig) {
        lock.withLock { recorded.append((model: cfg.modelName, baseURL: cfg.localBaseURL)) }
    }
}
