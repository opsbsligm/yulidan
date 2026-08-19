import Foundation
@testable import HarnessApp
import LLM
import Session
import Testing

// MARK: - AppViewModel 会话生命周期（场景测试：创建→对话→改名→切换→删除，含 DB 持久化 + 跨实例重载）

@MainActor
@Suite("AppViewModel 会话生命周期", .serialized)
struct AppViewModelSessionLifecycleTests {
    init() {
        // 只重置通知工厂；provider 走实例缝 providerFactoryOverride（不触碰静态工厂，防跨 suite 互踩）
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    // MARK: 临时资源 + 轮询助手

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-lifecycle-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-lifecycle-skills-\(UUID().uuidString)")
    }

    /// 轮询等待生成收敛（isGenerating 清零 + 末条为已投递助手消息）
    private func waitForGeneration(_ vm: AppViewModel, timeout: TimeInterval = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !vm.isGenerating,
               let last = vm.messages.last, last.role == .assistant, last.status == .delivered {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !vm.isGenerating && vm.messages.last?.role == .assistant
    }

    /// 轮询等待会话出现在 VM 列表（启动异步加载）
    private func waitForInitialLoad(_ vm: AppViewModel, _ id: SessionID, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if vm.sessions.contains(where: { $0.id == id }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return vm.sessions.contains(where: { $0.id == id })
    }

    /// 轮询等待 DB 中该会话持久化事件数达到 minCount（persistSession 为异步 Task）
    private func waitForDBEvents(_ db: SessionDB, _ id: SessionID, minCount: Int,
                                 timeout: TimeInterval = 10) async -> [SessionEvent]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let rec = try? await db.load(id), rec.events.count >= minCount {
                return rec.events
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await (try? db.load(id))?.events
    }

    // MARK: 场景 1：创建 → 对话 → DB 持久化 → 改名

    @Test("创建新会话 → 对话 → 事件持久化 DB → 重命名（UserDefaults 落盘）")
    func createMessageRename() async {
        let provider = PlainTextProvider()

        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local // hasAPIKey = true，走测试缝脚本化 LLM
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        // 1. 显式创建新会话：插入列表头部 + 选中 + 消息清空
        vm.createNewSession()
        #expect(vm.sessions.count == 1)
        #expect(vm.messages.isEmpty)
        guard let s1 = vm.selectedSession else {
            Issue.record("创建后会话未选中"); return
        }

        // 2. 对话：用户消息 → 脚本化回复 → 生成收敛
        vm.sendMessage("生命周期验证消息")
        #expect(await waitForGeneration(vm))
        #expect(vm.messages.count == 2)
        #expect(vm.messages.first?.role == .user)
        #expect(vm.messages.first?.content == "生命周期验证消息")
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.content == "你好！")
        #expect(vm.cachedLoopCountForTesting == 1) // 会话级 AgentLoop 缓存（LRU）

        // 3. DB 持久化：user + assistant 两条事件已落库
        if let db = try? SessionDB(dbURL: dbURL) {
            let events = await waitForDBEvents(db, s1.id, minCount: 2)
            let userCount = events?.filter { event in
                if case .userMessage = event {
                    return true
                }
                return false
            }.count
            let assistantCount = events?.filter { event in
                if case .assistantMessage = event {
                    return true
                }
                return false
            }.count
            #expect(userCount == 1)
            #expect(assistantCount == 1)
        } else {
            Issue.record("测试 DB 打开失败")
        }

        // 4. 重命名：存 UserDefaults（非 DB），标题立即生效
        let title = "生命周期测试会话-\(UUID().uuidString.prefix(8))"
        vm.renameSession(title)
        #expect(vm.sessionTitle(for: s1) == title)
        // 落盘验证：UserDefaults 中存在该键值
        let raw = UserDefaults.standard.data(forKey: "sessionTitles")
        #expect(raw != nil)
    }

    // MARK: 场景 2：会话切换重载

    @Test("会话切换：切回旧会话重载消息 + 改名标题保持")
    func switchSessionReload() async throws {
        let provider = PlainTextProvider()

        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        // 建立两个会话：s1 有一轮对话，s2 为空
        vm.createNewSession()
        guard let s1 = vm.selectedSession else {
            Issue.record("s1 创建失败"); return
        }
        vm.sendMessage("切换重载消息")
        #expect(await waitForGeneration(vm))
        let title = "切换会话-\(UUID().uuidString.prefix(8))"
        vm.renameSession(title)
        vm.createNewSession()
        #expect(vm.sessions.count == 2)
        #expect(vm.selectedSession?.id != s1.id)
        #expect(vm.messages.isEmpty)

        // 切回 s1：完整记录直接渲染（消息 + 标题重载）
        guard let s1rec = vm.sessions.first(where: { $0.id == s1.id }) else {
            Issue.record("s1 记录不在列表"); return
        }
        vm.selectSession(s1rec)
        #expect(vm.selectedSession?.id == s1.id)
        #expect(vm.messages.count == 2)
        #expect(vm.messages.first?.role == .user)
        #expect(vm.messages.first?.content == "切换重载消息")
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.content == "你好！")
        #expect(try vm.sessionTitle(for: #require(vm.selectedSession)) == title)

        // 切到 s2：空会话消息清空
        guard let s2rec = vm.sessions.first(where: { $0.id != s1.id }) else {
            Issue.record("s2 记录不在列表"); return
        }
        vm.selectSession(s2rec)
        // 空事件记录走 DB 拉取异步路径 → 轮询等待切换完成
        let d2 = Date().addingTimeInterval(10)
        while Date() < d2, vm.selectedSession?.id != s2rec.id {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.selectedSession?.id == s2rec.id)
        #expect(vm.messages.isEmpty)
    }

    // MARK: 场景 3：删除会话（DB 清理 + 循环回收 + 选中切换）

    @Test("删除会话：列表收缩 / 选中切换 / 循环即时回收 / DB 异步清理")
    func deleteSessionCleansUp() async {
        let provider = PlainTextProvider()

        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        // s1 有一轮对话（持有缓存循环），s2 为空
        vm.createNewSession()
        guard let s1 = vm.selectedSession else {
            Issue.record("s1 创建失败"); return
        }
        vm.sendMessage("删除前对话")
        #expect(await waitForGeneration(vm))
        #expect(vm.cachedLoopCountForTesting == 1)
        vm.createNewSession()
        guard let s2 = vm.selectedSession else {
            Issue.record("s2 创建失败"); return
        }

        // 删除 s1（此时选中）：列表收缩 + 选中切到 s2 + s1 循环即时 drop
        guard let s1rec = vm.sessions.first(where: { $0.id == s1.id }) else {
            Issue.record("s1 记录不在列表"); return
        }
        vm.deleteSession(s1rec)
        #expect(vm.sessions.count == 1)
        #expect(vm.cachedLoopCountForTesting == 0) // dropChatLoop 同步回收；s2 无对话无循环
        // 选中切换是异步（空事件记录先拉 DB 再切）→ 轮询等待
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, vm.selectedSession?.id != s2.id {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.selectedSession?.id == s2.id)
        #expect(vm.messages.isEmpty)

        // DB 异步清理：s1 记录消失，s2（空会话）仍在
        if let db = try? SessionDB(dbURL: dbURL) {
            let d2 = Date().addingTimeInterval(10)
            while Date() < d2 {
                let rec = try? await db.load(s1.id)
                if rec == nil {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            let deletedRec = try? await db.load(s1.id)
            #expect(deletedRec == nil)
            let keptRec = try? await db.load(s2.id)
            #expect(keptRec != nil)
        } else {
            Issue.record("测试 DB 打开失败")
        }
    }

    // MARK: 场景 4：跨实例重载（模拟 App 重启：启动元数据加载 → 按需拉事件 + 标题持久）

    @Test("跨实例重载：启动仅元数据 → 选中按需拉 DB 事件 + 改名标题跨实例持久")
    func crossInstanceReload() async throws {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let id = SessionID()
        // 预置 DB：user + assistant 两条事件
        if let db = try? SessionDB(dbURL: dbURL) {
            var rec = SessionRecord(id: id, metadata: SessionMetadata(cwd: URL(fileURLWithPath: "/tmp")))
            rec.append(.userMessage(UserMessage(content: [.text("重启重载测试消息")])))
            rec.append(.assistantMessage(AssistantMessage(turn: 1, step: 0,
                                                          content: [.text("跨重启助手回复")],
                                                          provider: "local", model: "test-model")))
            try await db.save(rec)
        } else {
            Issue.record("测试 DB 打开失败"); return
        }

        // 实例 1：启动列表仅元数据（性能优化）→ selectSession 触发按需拉事件
        let vm1 = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        guard await waitForInitialLoad(vm1, id) else {
            Issue.record("实例1 启动加载未完成"); return
        }
        guard let rec = vm1.sessions.first(where: { $0.id == id }) else {
            Issue.record("会话不在列表"); return
        }
        #expect(rec.events.isEmpty) // 启动加载不含事件
        vm1.selectSession(rec)
        let d1 = Date().addingTimeInterval(10)
        while Date() < d1, vm1.messages.count != 2 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm1.messages.count == 2)
        #expect(vm1.messages.first?.content == "重启重载测试消息")
        #expect(vm1.messages.last?.content == "跨重启助手回复")

        // 改名 → UserDefaults 持久；实例 2（模拟重启）读回
        let title = "重载会话-\(UUID().uuidString.prefix(8))"
        vm1.renameSession(title)
        #expect(vm1.sessionTitle(for: rec) == title)

        let vm2 = AppViewModel(skillUserDirectory: tempSkillDir(), sessionDBURL: dbURL)
        guard await waitForInitialLoad(vm2, id) else {
            Issue.record("实例2 启动加载未完成"); return
        }
        guard let rec2 = vm2.sessions.first(where: { $0.id == id }) else {
            Issue.record("实例2 会话不在列表"); return
        }
        #expect(vm2.sessionTitle(for: rec2) == title) // 标题跨实例持久
        // 实例 2 同样按需拉事件
        vm2.selectSession(rec2)
        let d2 = Date().addingTimeInterval(10)
        while Date() < d2, vm2.messages.count != 2 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm2.messages.count == 2)
        #expect(vm2.messages.last?.content == "跨重启助手回复")
    }

    // MARK: 场景 5：空文本 no-op + 无选中会话时自动创建

    @Test("空文本不建会话不发请求 + 无选中会话发送时自动创建并完成对话")
    func emptyTextAndAutoCreate() async {
        let provider = PlainTextProvider()

        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        // 空文本：直接 return，不建会话、不发 LLM 请求
        vm.sendMessage("   \n ")
        // 等待启动加载窗口过去（空 DB 加载很快），防止异步加载干扰断言
        try? await Task.sleep(for: .milliseconds(300))
        #expect(vm.sessions.isEmpty)
        #expect(vm.selectedSession == nil)
        #expect(vm.messages.isEmpty)
        #expect(provider.requestCount == 0)

        // 非空文本 + 无选中会话 → 自动创建会话并完成对话
        vm.sendMessage("自动创建验证")
        #expect(vm.sessions.count == 1)
        #expect(vm.selectedSession != nil)
        #expect(await waitForGeneration(vm))
        #expect(vm.messages.count == 2)
        #expect(vm.messages.first?.content == "自动创建验证")
        #expect(vm.messages.last?.content == "你好！")
        #expect(vm.cachedLoopCountForTesting == 1)

        // autoTitle 派生标题 + 空串改名 no-op（trim 后为空忽略）
        guard let s = vm.selectedSession else {
            Issue.record("自动创建后会话未选中"); return
        }
        let autoTitle = vm.sessionTitle(for: s)
        #expect(autoTitle == "自动创建验证")
        vm.renameSession("   ")
        #expect(vm.sessionTitle(for: s) == autoTitle)
    }
}
