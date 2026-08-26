import Foundation
import Session
import Skill
import Testing
import Tools

// MARK: - 覆盖审计轮 17：Skill 旧版解码 + SkillStore 解析/加载兜底 + SkillTools 参数兜底

@Suite("Skill R17 Gap Coverage")
struct SkillR17GapTests {
    private func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    /// ① 旧版 Skill JSON（无 tags/version 字段）→ `?? []` / `?? 1` 解码兜底
    @Test("Skill: 旧版 JSON 无 tags/version → 解码兜底")
    func legacySkillDecode() throws {
        let json = #"{"name":"legacy-skill","description":"旧数据","instructions":"正文","source":"user"}"#
        let skill = try JSONDecoder().decode(Skill.self, from: Data(json.utf8))
        #expect(skill.tags.isEmpty)
        #expect(skill.version == 1)
    }

    /// ② parse：tags 行（`.map{trim}` 闭包）+ 非法 version（`Int(...) ?? 1` 兜底）
    @Test("SkillStore.parse: tags 解析 + 非法 version 兜底为 1")
    func parseTagsAndInvalidVersion() {
        let text = """
        ---
        name: r17-parsed
        description: 覆盖审计轮 17
        tags: git, commit, 部署
        version: abc
        ---
        正文内容
        """
        let skill = SkillStore.parse(text, source: "r17")
        #expect(skill?.name == "r17-parsed")
        #expect(skill?.tags == ["git", "commit", "部署"]) // map 闭包命中
        #expect(skill?.version == 1) // Int("abc") 失败 → ?? 1
    }

    /// ③ load：路径是文件（非目录）→ loadThrowing 抛 notDirectory → `?? []` 兜底返回空
    @Test("SkillStore.load: 路径为文件 → notDirectory 抛错 → 空数组兜底")
    func loadFromFilePathReturnsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-r17-skill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("not-a-dir.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let skills = SkillStore.load(from: file)
        #expect(skills.isEmpty)
    }

    /// ④ loadThrowing：目录含合法 SKILL.md 子目录 → compactMap 闭包执行（既有测试均空目录）
    @Test("SkillStore.loadThrowing: 非空目录 → compactMap 闭包命中")
    func loadThrowingWithEntries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-r17-skillload-\(UUID().uuidString)", isDirectory: true)
        let skillDir = root.appendingPathComponent("r17-load-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let md = """
        ---
        name: r17-load-skill
        description: 目录加载
        ---
        正文
        """
        try md.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skills = try SkillStore.loadThrowing(from: root)
        #expect(skills.count == 1)
        #expect(skills.first?.name == "r17-load-skill")
    }

    /// ⑤ use_skill：缺 name 参数 → `args["name"] ?? ""` 兜底
    @Test("use_skill: 缺 name 参数 → 兜底空串 → invalid_args")
    func useSkillMissingName() async throws {
        let tool = UseSkillTool(registry: SkillRegistry())
        let result = try await tool.execute([:], context: context())
        #expect(result.error?.code == "invalid_args")
    }

    /// ⑥ save_skill：缺 name → 兜底；saveRoot=nil（默认）→ `?? userSkillsDirectory` 兜底
    @Test("save_skill: 缺参兜底 + 默认 saveRoot 兜底")
    func saveSkillFallbacks() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-r17-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let prev = ProcessInfo.processInfo.environment["HARNESS_HOME"]
        setenv("HARNESS_HOME", home.path, 1)
        defer {
            if let prev {
                setenv("HARNESS_HOME", prev, 1)
            } else {
                unsetenv("HARNESS_HOME")
            }
        }

        let registry = SkillRegistry()
        let tool = SaveSkillTool(registry: registry) // saveRoot 默认 nil
        let missing = try await tool.execute(["description": "d", "instructions": "i"], context: context())
        #expect(missing.error?.code == "invalid_args") // name ?? "" 命中

        let ok = try await tool.execute(
            ["name": "r17-saved", "description": "d", "instructions": "i"],
            context: context()
        )
        #expect(ok.error == nil) // saveRoot ?? userSkillsDirectory（HARNESS_HOME 隔离）命中
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).contains(".harness"))
    }

    /// ⑦ debug_skill：缺 name 兜底 + 有结构性问题技能 → `count(where:)` 闭包命中
    @Test("debug_skill: 缺参兜底 + 问题技能 count(where:) 闭包")
    func debugSkillIssues() async throws {
        let registry = SkillRegistry()
        // 大写 + 空格 name（warning）+ 空 description（error）→ issues 非空
        _ = await registry.register(Skill(name: "Bad Name", description: "", instructions: "正文", source: "test"))
        let tool = DebugSkillTool(registry: registry)

        let missing = try await tool.execute([:], context: context())
        #expect(missing.error?.code == "invalid_args")

        let report = try await tool.execute(["name": "Bad Name"], context: context())
        #expect(report.meta?["passed"] == "false")
        #expect(Int(report.meta?["errors"] ?? "0") == 1)
    }
}
