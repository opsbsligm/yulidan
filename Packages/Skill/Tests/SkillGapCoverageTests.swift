import Foundation
import Session
import Skill
import Testing
import Tools

// MARK: - Skill 包薄弱分支覆盖（覆盖审计轮 8）

@Suite("Skill Gap Coverage")
struct SkillGapCoverageTests {
    /// 隔离临时根目录（测试结束清理）
    private func makeRoot() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skillgap-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var ctx: ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    /// ① userSkillsDirectory：HARNESS_HOME 环境变量分支（L18 expandingTildeInPath 路径）
    @Test("HARNESS_HOME 环境变量覆盖：用户技能目录落在 env 路径下 .harness/skills")
    func harnessHomeEnvOverride() async {
        let prev = ProcessInfo.processInfo.environment["HARNESS_HOME"]
        let home = makeRoot()
        let expected = home.appendingPathComponent(".harness/skills", isDirectory: true)
        setenv("HARNESS_HOME", home.path, 1)
        defer {
            if let prev {
                setenv("HARNESS_HOME", prev, 1)
            } else {
                unsetenv("HARNESS_HOME")
            }
            try? FileManager.default.removeItem(at: home)
        }
        // 进程级静态 override 存在并发窗（先例口径）：短暂重试吸收其他套件瞬时占用
        var dir = SkillStore.userSkillsDirectory
        for _ in 0 ..< 40 where dir.path != expected.path {
            try? await Task.sleep(nanoseconds: 50_000_000)
            dir = SkillStore.userSkillsDirectory
        }
        #expect(dir.path == expected.path)
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    /// ② delete：removeItem 抛错（权限拒绝）→ catch 分支 return false 且目录保留
    @Test("delete：目录只读删除失败 → false 且目录保留（恢复权限后可删）")
    func deleteFailureReturnsFalse() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try SkillStore.save(Skill(name: "ro-skill", description: "只读删除测试",
                                  instructions: "正文", source: "t"), to: root)
        let dir = SkillStore.skillDirectory(for: "ro-skill", root: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(SkillStore.delete("ro-skill", from: root) == false)
        #expect(FileManager.default.fileExists(atPath: dir.path))
        // 恢复权限后删除成功
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        #expect(SkillStore.delete("ro-skill", from: root) == true)
        #expect(FileManager.default.fileExists(atPath: dir.path) == false)
    }

    /// ③ save_skill：保存根不可写 → SkillStore.save 抛错 → save_failed 错误回传
    @Test("save_skill：保存根父目录只读 → save_failed 错误码回传")
    func saveSkillSaveFailed() async throws {
        let parent = makeRoot()
        let ro = parent.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ro.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro.path)
            try? FileManager.default.removeItem(at: parent)
        }
        let tool = SaveSkillTool(registry: SkillRegistry(),
                                 saveRoot: ro.appendingPathComponent("skills"))
        let result = try await tool.execute(["name": "x-skill", "description": "描述",
                                             "instructions": "正文"],
                                            context: ctx)
        #expect(result.error?.code == "save_failed")
        #expect(ToolResult.text(of: result).contains("保存失败"))
    }

    /// ④ debug_skill：name 缺失（纯空白）→ invalid_args
    @Test("debug_skill：name 缺失（纯空白）→ invalid_args 错误码回传")
    func debugSkillMissingName() async throws {
        let tool = DebugSkillTool(registry: SkillRegistry())
        let missing = try await tool.execute([:], context: ctx)
        #expect(missing.error?.code == "invalid_args")
        #expect(ToolResult.text(of: missing).contains("缺少必填参数 name"))
        let blank = try await tool.execute(["name": "   "], context: ctx)
        #expect(blank.error?.code == "invalid_args")
    }

    /// ⑤ SkillDebugger：正文首尾空白 → 序列化往返不一致 error（debugRun 判不通过）
    @Test("SkillDebugger：正文首尾空白 → 往返不一致 error，debugRun 不通过")
    func roundTripMismatchDetected() {
        let skill = Skill(name: "rt-skill", description: "往返测试",
                          instructions: "  正文带首尾空白  ", source: "t")
        let issues = SkillDebugger.validate(skill)
        #expect(issues.contains { $0.severity == .error && $0.message == "正文序列化往返不一致" })
        let report = SkillDebugger.debugRun(skill, sampleInput: "")
        #expect(report.passed == false)
        #expect(report.text.contains("正文序列化往返不一致"))
        // 对照：无首尾空白的正文往返一致，无 error
        let clean = Skill(name: "clean-skill", description: "对照",
                          instructions: "干净正文", source: "t")
        #expect(SkillDebugger.debugRun(clean, sampleInput: "输入").passed == true)
    }

    /// ⑥ SkillVersionRecord.id 转发属性（= version）
    @Test("SkillVersionRecord.id 转发 version")
    func versionRecordIDForwards() {
        let record = SkillVersionRecord(version: 3, changeNote: "第三次迭代",
                                        description: "描述", instructions: "正文")
        #expect(record.id == 3)
    }
}

private extension ToolResult {
    /// 拼接全部 text 片段（各测试文件自带同款助手）
    static func text(of result: ToolResult) -> String {
        result.content.compactMap { part in
            if case let .text(s) = part {
                return s
            }
            return nil
        }.joined(separator: "\n")
    }
}
