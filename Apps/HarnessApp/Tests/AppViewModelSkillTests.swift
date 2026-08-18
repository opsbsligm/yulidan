import Foundation
@testable import HarnessApp
import Skill
import Testing

// MARK: - AppViewModel 技能管理（保存/删除/校验）

@MainActor
@Suite("AppViewModel 技能管理（真实文件系统 + 注册表）", .serialized)
struct AppViewModelSkillTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    /// 独立临时用户技能目录（先设覆盖，再建 VM，避免读到真实目录）
    private func freshDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-skill-test-\(UUID().uuidString)")
        SkillStore.userSkillsDirectoryOverride = url
        return url
    }

    private func cleanup(_ dir: URL) {
        SkillStore.userSkillsDirectoryOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// 轮询直到技能出现/消失（后台注册 Task 是异步的）
    private func waitForSkill(_ vm: AppViewModel, name: String, expectPresent: Bool,
                              timeout: TimeInterval = 3) async -> Skill? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await vm.refreshSkills()
            if let item = vm.skills.first(where: { $0.name == name }) {
                if expectPresent {
                    return item
                }
            } else if !expectPresent {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return expectPresent ? nil : vm.skills.first
    }

    @Test("saveUserSkill：slug 化 + 写 SKILL.md + 注册 + 列表刷新")
    func saveSkill() async {
        let dir = freshDir()
        defer { cleanup(dir) }
        let vm = AppViewModel()
        vm.saveUserSkill(name: "Daily Report", description: "生成日报", tags: "报告, 日报",
                         instructions: "步骤：\n1. 收集数据\n2. 输出报告")
        guard let item = await waitForSkill(vm, name: "daily-report", expectPresent: true) else {
            Issue.record("技能未出现在列表")
            return
        }
        #expect(item.description == "生成日报")
        #expect(item.tags == ["报告", "日报"])
        // 磁盘上的 SKILL.md 可被 parse 回读
        let file = dir.appendingPathComponent("daily-report/SKILL.md")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let parsed = SkillStore.parse(text, source: file.path)
        #expect(parsed?.name == "daily-report")
        #expect(parsed?.instructions.contains("1. 收集数据") == true)
    }

    @Test("deleteUserSkill：删目录 + 反注册")
    func deleteSkill() async throws {
        let dir = freshDir()
        defer { cleanup(dir) }
        let vm = AppViewModel()
        vm.saveUserSkill(name: "temp-skill", description: "待删除", tags: "", instructions: "正文")
        guard await waitForSkill(vm, name: "temp-skill", expectPresent: true) != nil else {
            Issue.record("保存失败")
            return
        }
        let file = dir.appendingPathComponent("temp-skill/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: file.path))
        let target = vm.skills.first { $0.name == "temp-skill" }
        try vm.deleteUserSkill(#require(target))
        await waitForSkill(vm, name: "temp-skill", expectPresent: false)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }

    /// 轮询直到内置技能注册完成（注册发生在启动后台 Task）
    private func waitForBuiltIn(_ vm: AppViewModel, timeout: TimeInterval = 3) async -> Skill? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await vm.refreshSkills()
            if let item = vm.skills.first(where: { $0.source == "builtin" }) {
                return item
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    @Test("内置技能不可删除（toast 提示且保留）")
    func deleteBuiltInRejected() async {
        let dir = freshDir()
        defer { cleanup(dir) }
        let vm = AppViewModel()
        guard let builtIn = await waitForBuiltIn(vm) else {
            Issue.record("未找到内置技能")
            return
        }
        vm.deleteUserSkill(builtIn)
        #expect(vm.toastMessage == "内置技能不可删除")
        await vm.refreshSkills()
        #expect(vm.skills.contains { $0.name == builtIn.name })
    }

    @Test("空正文被 toast 拦截且不写文件")
    func emptyBodyRejected() {
        let dir = freshDir()
        defer { cleanup(dir) }
        let vm = AppViewModel()
        vm.saveUserSkill(name: "empty-body", description: "x", tags: "", instructions: "   ")
        #expect(vm.toastMessage == "技能正文不能为空")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(entries.isEmpty)
    }
}
