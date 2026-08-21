import Foundation
@testable import HarnessApp
import Testing

// MARK: - AppViewModel 导航 Tab 加载三态（P0.3 异常 UI：加载中 / 已加载 / 加载失败 + 重试）

@MainActor
@Suite("AppViewModel 导航加载三态", .serialized)
struct AppViewModelNavLoadStateTests {
    init() {
        // 通知走 Noop（复用 AppViewModelSubagentTests 的测试替身；不触碰 provider 静态工厂）
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-navload-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-navload-skills-\(UUID().uuidString)")
    }

    /// 轮询等待条件成立（主 Actor；超时后由 #expect 暴露）
    private func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: 场景 1：启动后四个导航 Tab 全部进入 .loaded

    @Test("启动加载：会话/插件/技能/工具四态全部进入 loaded")
    func startupLoadsAllTabs() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)

        await waitUntil {
            vm.sessionsLoadState.isLoaded
                && vm.pluginsLoadState.isLoaded
                && vm.skillsLoadState.isLoaded
                && vm.toolsLoadState.isLoaded
        }
        #expect(vm.sessionsLoadState == .loaded)
        #expect(vm.pluginsLoadState == .loaded)
        #expect(vm.skillsLoadState == .loaded)
        #expect(vm.toolsLoadState == .loaded)
        // 技能页：内置技能必须可用（用户目录为空不影响）
        #expect(!vm.skills.isEmpty)
        // 工具页：内置 + MCP 演示 + RAG + 记忆工具应全部注册
        #expect(vm.tools.count >= 10)
    }

    // MARK: 场景 2：会话 DB 路径被普通文件占用 → failed → 重试仍 failed → 移除文件后重试恢复 loaded

    @Test("会话 DB 被文件占用：failed 态 + 重试恢复")
    func sessionDBBlockedByFile() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()

        // 在 DB 路径放置一个非 SQLite 文件（模拟数据库损坏/被占用）
        try? "this is not a sqlite database".write(toFile: dbURL.path, atomically: true, encoding: .utf8)

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)

        await waitUntil { !vm.sessionsLoadState.isLoading }
        #expect(vm.sessionsLoadState == .failed("无法打开会话数据库"))

        // 文件仍在 → 重试必然仍失败（状态链路：loading → failed）
        await vm.retryLoadSessions()
        #expect(vm.sessionsLoadState == .failed("无法打开会话数据库"))

        // 移除坏文件 → 重试 → 全新空库加载成功
        try? FileManager.default.removeItem(at: dbURL)
        await vm.retryLoadSessions()
        #expect(vm.sessionsLoadState == .loaded)
    }

    // MARK: 场景 3：用户技能目录被普通文件占用 → failed（内置技能仍在）→ 换成目录后重试恢复

    @Test("用户技能目录被文件占用：failed 态 + 内置技能保留 + 重试恢复")
    func skillDirectoryBlockedByFile() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        // 技能目录路径上放一个普通文件（模拟目录损坏）
        try? "not a directory".write(toFile: skillDir.path, atomically: true, encoding: .utf8)

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)

        await waitUntil { !vm.skillsLoadState.isLoading }
        guard case let .failed(msg) = vm.skillsLoadState else {
            Issue.record("期望 skillsLoadState 为 .failed，实际：\(vm.skillsLoadState)")
            return
        }
        #expect(msg.contains("用户技能加载失败"))
        // 内置技能不受用户目录故障影响
        #expect(!vm.skills.isEmpty)
        #expect(vm.skills.allSatisfy { $0.source == "builtin" })

        // 同路径换成目录 → 重试恢复
        try? FileManager.default.removeItem(at: skillDir)
        try? FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        await vm.retryLoadSkills()
        #expect(vm.skillsLoadState == .loaded)
    }
}
