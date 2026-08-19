import Foundation
@testable import HarnessApp
import LLM
import Testing

// MARK: - AppViewModel 生成取消 + 通知开关（场景测试：stopGenerating 在途取消 / 通知开关同步协调器）

/// 慢速 LLM：1.5s 延迟后返回（取消后在后台自行完成——AgentLoop.cancel 设计语义：
/// 在途 LLM 调用不中断，whenIdle 立即唤醒；延迟响应不得污染会话）
private final class SlowCancellableProvider: LLMProvider, @unchecked Sendable {
    let id = "slow-cancellable"
    let supportedModels = ["test-model"]
    private let lock = NSLock()
    private var count = 0
    private var finishedFlag = false

    var requestCount: Int {
        lock.withLock { count }
    }

    var finished: Bool {
        lock.withLock { finishedFlag }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        lock.withLock { count += 1 }
        try? await Task.sleep(for: .seconds(1.5))
        lock.withLock { finishedFlag = true }
        return LLMResponse(model: "test-model", content: [.text("慢速回答")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
@Suite("AppViewModel 生成取消与通知开关", .serialized)
struct AppViewModelCancelNotificationsTests {
    init() {
        // 只重置通知工厂；provider 走实例缝（不触碰静态工厂，防跨 suite 互踩）
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-cancel-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-cancel-skills-\(UUID().uuidString)")
    }

    // MARK: 场景 1：生成中途 stopGenerating（在途取消）

    @Test("stopGenerating：isGenerating 立即清零 + 在途调用后台完成后延迟响应不污染会话")
    func stopGeneratingMidGeneration() async {
        let provider = SlowCancellableProvider()
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.llmConfig.provider = .local
        vm.providerFactoryOverride = { _, _ in provider }
        defer { vm.providerFactoryOverride = nil }

        vm.sendMessage("慢速问题")
        // 等生成真正进入 LLM 调用（request 已发出）
        let d0 = Date().addingTimeInterval(10)
        while Date() < d0, provider.requestCount < 1 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(provider.requestCount == 1)
        #expect(vm.isGenerating)

        // 中途停止：isGenerating 同步清零
        vm.stopGenerating()
        #expect(vm.isGenerating == false)

        // 设计语义（AgentLoop.cancel）：在途 LLM 调用后台自行完成，不中断。
        // 等待其完成（~1.5s）+ 稳定窗口，验证延迟响应**不**被追加进会话
        let d1 = Date().addingTimeInterval(10)
        while Date() < d1, !provider.finished {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(provider.finished)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(provider.requestCount == 1) // 取消后不再发起新请求

        // 延迟到达的"慢速回答"不得污染会话：无助手消息残留，无错误消息
        #expect(vm.messages.count == 1)
        #expect(vm.messages.last?.role == .user)
        #expect(vm.generationError == nil) // 取消路径不置错误
    }

    // MARK: 场景 2：通知开关联动 NotificationCoordinator

    @Test("通知开关：关闭/开启同步到 NotificationCoordinator.isEnabled（UserDefaults 持久）")
    func notificationsToggleSyncsCoordinator() async {
        // UserDefaults 全局态：保存当前值，结束恢复
        let prev = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool
        defer {
            if let prev {
                UserDefaults.standard.set(prev, forKey: "notificationsEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "notificationsEnabled")
            }
        }

        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)

        // 关闭 → 协调器异步同步
        vm.setNotificationsEnabled(false)
        #expect(vm.notificationsEnabled == false) // UserDefaults 同步落盘
        let d1 = Date().addingTimeInterval(10)
        while Date() < d1, await vm.notificationCenter.isEnabled != false {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(await vm.notificationCenter.isEnabled == false)

        // 开启 → 协调器恢复（开启路径额外触发 ensureAuthorization 授权请求）
        vm.setNotificationsEnabled(true)
        #expect(vm.notificationsEnabled == true)
        let d2 = Date().addingTimeInterval(10)
        while Date() < d2, await vm.notificationCenter.isEnabled != true {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(await vm.notificationCenter.isEnabled == true)
    }
}
