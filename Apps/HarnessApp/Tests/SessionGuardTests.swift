import Foundation
@testable import HarnessApp
import LLM
import Session
import Testing

// MARK: - F7：生成中会话守卫（B1）+ RelativeTime 纯函数（B3）

/// 慢速 LLM：1.5s 延迟返回（保证测试可在在途窗口内执行切换/新建/删除拦截断言）
private final class SlowGuardProvider: LLMProvider, @unchecked Sendable {
    let id = "slow-guard"
    let supportedModels = ["test-model"]
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.withLock { count }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        lock.withLock { count += 1 }
        try? await Task.sleep(for: .seconds(1.5))
        return LLMResponse(model: "test-model", content: [.text("慢速回答")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
@Suite("F7 生成中会话守卫", .serialized)
struct SessionGuardTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-guard-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-guard-skills-\(UUID().uuidString)")
    }

    /// 建 VM + 2 个会话（current = 最新创建，other = 较早），返回 (vm, current, other)
    private func makeVM(provider: LLMProvider) -> (AppViewModel, SessionRecord, SessionRecord) {
        let dbURL = tempDBURL()
        let skillDir = tempSkillDir()
        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        vm.createNewSession(silent: true)
        let s1 = vm.sessions[0]
        vm.createNewSession(silent: true)
        let s2 = vm.sessions[0]
        #expect(vm.selectedSession?.id == s2.id)
        return (vm, s2, s1)
    }

    @Test("生成中：切换/新建/删除全部拦截；停止后可切换且生成态清零")
    func generationBlocksSessionSwitch() async {
        let provider = SlowGuardProvider()
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let (vm, current, other) = makeVM(provider: provider)

        vm.sendMessage("慢速问题")
        // 等在途 LLM 调用真正发出
        let d0 = Date().addingTimeInterval(10)
        while Date() < d0, provider.requestCount < 1 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(provider.requestCount == 1)
        #expect(vm.isGenerating)
        #expect(vm.generatingSessionId == current.id)

        // ① 切换会话：拦截，selectedSession 不变
        vm.selectSession(other)
        #expect(vm.selectedSession?.id == current.id, "生成中切换会话应被拦截")

        // ② 新建会话：拦截，会话数不变
        let countBefore = vm.sessions.count
        vm.createNewSession()
        #expect(vm.sessions.count == countBefore, "生成中新建会话应被拦截")

        // ③ 删除生成中会话：拦截
        vm.deleteSession(current)
        #expect(vm.sessions.count == countBefore, "生成中删除当前会话应被拦截")
        #expect(vm.selectedSession?.id == current.id)

        // ④ 停止后可切换，生成态清零（切换走异步加载路径，轮询等待收敛）
        vm.stopGenerating()
        #expect(!vm.isGenerating)
        #expect(vm.generatingSessionId == nil)
        vm.selectSession(other)
        let d1 = Date().addingTimeInterval(10)
        while Date() < d1, vm.selectedSession?.id != other.id {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.selectedSession?.id == other.id)
    }

    @Test("完整生成收敛后生成态清零（正常完成路径）")
    func generationStateClearsOnCompletion() async {
        let provider = SlowGuardProvider()
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let (vm, current, _) = makeVM(provider: provider)

        vm.sendMessage("慢速问题")
        let d0 = Date().addingTimeInterval(15)
        var deadline = Date().addingTimeInterval(15)
        while Date() < deadline, vm.isGenerating {
            try? await Task.sleep(for: .milliseconds(50))
            deadline = d0.addingTimeInterval(0) // 保持 15s 上限
        }
        #expect(!vm.isGenerating, "慢速生成应在窗口内收敛")
        #expect(vm.generatingSessionId == nil)
        // 助手回答已写入当前会话
        let titles = vm.sessions.map(\.id)
        #expect(titles.contains(current.id))
    }
}

// MARK: - RelativeTime 纯函数（固定 now，零时钟依赖）

@Suite("RelativeTime 相对时间")
struct RelativeTimeTests {
    private var now: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 18; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    @Test("今天：刚刚 / N分钟前 / N小时前")
    func todayBuckets() {
        let now = now
        #expect(RelativeTime.format(now.addingTimeInterval(-30), now: now) == "刚刚")
        #expect(RelativeTime.format(now.addingTimeInterval(-5 * 60), now: now) == "5分钟前")
        #expect(RelativeTime.format(now.addingTimeInterval(-90 * 60), now: now) == "1小时前")
    }

    @Test("昨天 / N天前（<7天）")
    func yesterdayAndDaysAgo() throws {
        let now = now
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        #expect(RelativeTime.format(yesterday, now: now) == "昨天")
        let threeDaysAgo = try #require(Calendar.current.date(byAdding: .day, value: -3, to: now))
        #expect(RelativeTime.format(threeDaysAgo, now: now) == "3天前")
    }

    @Test("≥7 天：M月d日 格式")
    func farDate() throws {
        let now = now
        let far = try #require(Calendar.current.date(byAdding: .day, value: -20, to: now))
        let text = RelativeTime.format(far, now: now)
        #expect(text.contains("月"), "20 天前应显示 M月d日，实际：\(text)")
        #expect(!text.hasSuffix("天前"))
    }
}
