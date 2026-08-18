import ArgumentParser
import Foundation
import Skill

// MARK: - skills 扩展子命令（模块7：调试 / 版本历史 / 回滚 / 删除）

/// 加载「内置 + 用户目录」技能注册表（与 dsh skills list 同源）
private func loadSkillRegistry() async -> SkillRegistry {
    let registry = SkillRegistry()
    for skill in SkillsCLI.allSkills() {
        await registry.register(skill)
    }
    return registry
}

/// 版本历史时间戳格式
private let historyDateFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

/// dsh skills debug <名称> [--sample 样例]：结构校验 + 提示词预览（不消耗 LLM 调用）
struct SkillsDebugCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "debug",
        abstract: "Debug-run a skill (structure validation + prompt preview)"
    )

    @Argument(help: "Skill name")
    var name: String

    @Option(name: .long, help: "Sample task input rendered into the preview")
    var sample: String?

    func run() async throws {
        let registry = await loadSkillRegistry()
        guard let skill = await registry.skill(named: name) else {
            print("技能不存在：\(name)（可用：dsh skills list）")
            throw ExitCode(1)
        }
        let report = SkillDebugger.debugRun(skill, sampleInput: sample ?? "")
        print(report.text)
        if !report.passed {
            throw ExitCode(1)
        }
    }
}

/// dsh skills versions <名称>：查看版本历史
struct SkillsVersionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "versions",
        abstract: "Show a skill's version history"
    )

    @Argument(help: "Skill name")
    var name: String

    func run() async throws {
        let history = SkillVersioning.loadHistory(directory: SkillStore.skillDirectory(for: name))
        guard !history.isEmpty else {
            print("\(name) 无版本历史（保存/更新/回滚操作会记录历史）")
            return
        }
        print("\(name) 版本历史（共 \(history.count) 条）：")
        for record in history {
            print("  v\(record.version)  [\(historyDateFormat.string(from: record.changedAt))]  \(record.changeNote)")
        }
    }
}

/// dsh skills restore <名称> -v <N>：回滚到某版本（生成新版本，不销毁历史）
struct SkillsRestoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Roll a skill back to a version (creates a new version; history preserved)"
    )

    @Argument(help: "Skill name")
    var name: String

    @Option(name: .shortAndLong, help: "Version number to restore from")
    var version: Int

    func run() async throws {
        let registry = await loadSkillRegistry()
        guard let current = await registry.skill(named: name) else {
            print("技能不存在：\(name)")
            throw ExitCode(1)
        }
        do {
            guard let restored = try SkillVersioning.restore(name: name, to: version, current: current) else {
                print("版本 v\(version) 不存在（查看：dsh skills versions \(name)）")
                throw ExitCode(1)
            }
            _ = await registry.register(restored)
            print("✅ \(name) 已回滚 v\(version) 内容 → 生成 v\(restored.version)（历史保留）")
        } catch {
            print("回滚失败：\(error.localizedDescription)")
            throw ExitCode(1)
        }
    }
}

/// dsh skills delete <名称>：删除用户技能（内置技能不可删）
struct SkillsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a user skill (built-in skills are protected)"
    )

    @Argument(help: "Skill name")
    var name: String

    func run() async throws {
        let registry = await loadSkillRegistry()
        guard let skill = await registry.skill(named: name) else {
            print("技能不存在：\(name)")
            throw ExitCode(1)
        }
        guard skill.source != "builtin" else {
            print("内置技能不可删除")
            throw ExitCode(1)
        }
        guard SkillStore.delete(name) else {
            print("删除失败：技能目录不存在（来源：\(skill.source)）")
            throw ExitCode(1)
        }
        _ = await registry.remove(name)
        print("✅ 技能 \(name) 已删除")
    }
}
