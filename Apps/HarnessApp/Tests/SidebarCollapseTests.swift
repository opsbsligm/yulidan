import Foundation
@testable import HarnessApp
import Testing

// MARK: - F8：侧边栏折叠态（UserDefaults 持久化 + 跨实例读取）

@MainActor
@Suite("F8 侧边栏折叠", .serialized)
struct SidebarCollapseTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-collapse-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-collapse-skills-\(UUID().uuidString)")
    }

    @Test("折叠态默认展开；置位后 UserDefaults 持久化且新实例可读")
    func collapseStatePersistsAcrossInstances() {
        // UserDefaults 全局态：保存当前值，结束恢复
        let prev = UserDefaults.standard.object(forKey: "sidebarCollapsed") as? Bool
        defer {
            if let prev {
                UserDefaults.standard.set(prev, forKey: "sidebarCollapsed")
            } else {
                UserDefaults.standard.removeObject(forKey: "sidebarCollapsed")
            }
        }
        UserDefaults.standard.removeObject(forKey: "sidebarCollapsed")

        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        // 默认展开
        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        #expect(!vm.isSidebarCollapsed)

        // 折叠 → 持久化
        vm.isSidebarCollapsed = true
        #expect(UserDefaults.standard.bool(forKey: "sidebarCollapsed"))

        // 新实例读取持久化状态
        let vm2 = AppViewModel(skillUserDirectory: tempSkillDir(), sessionDBURL: tempDBURL())
        #expect(vm2.isSidebarCollapsed)

        // 展开 → 持久化清零
        vm2.isSidebarCollapsed = false
        #expect(!UserDefaults.standard.bool(forKey: "sidebarCollapsed"))
    }
}
