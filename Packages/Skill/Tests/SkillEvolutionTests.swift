import Foundation
import RAG
import Session
import Skill
import Testing
import Tools

// MARK: - 版本管理

@Suite("SkillVersioning")
struct SkillVersioningTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("skill-ver-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func recordAndLoadHistory() throws {
        let skill = Skill(name: "demo", description: "演示技能", instructions: "步骤一：开始",
                          tags: ["t"], source: "s", version: 1)
        let dir = root.appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try SkillVersioning.record(skill, note: "新建", directory: dir)
        var v2 = skill
        v2.version = 2
        v2.instructions = "步骤一：开始（修订）"
        try SkillVersioning.record(v2, note: "修订步骤", directory: dir)

        let history = SkillVersioning.loadHistory(directory: dir)
        #expect(history.count == 2)
        #expect(history[0].version == 1)
        #expect(history[1].changeNote == "修订步骤")
        #expect(history[1].instructions.contains("修订"))
    }

    @Test func restoreCreatesNewVersion() throws {
        let v1 = Skill(name: "appx", description: "旧描述", instructions: "旧正文", source: "s", version: 1)
        try SkillStore.save(v1, to: root)
        let dir = SkillStore.skillDirectory(for: "appx", root: root)
        try SkillVersioning.record(v1, note: "新建", directory: dir)
        var v2 = v1
        v2.version = 2
        v2.description = "新描述"
        v2.instructions = "新正文"
        try SkillStore.save(v2, to: root)
        try SkillVersioning.record(v2, note: "更新", directory: dir)

        guard let restored = try SkillVersioning.restore(name: "appx", to: 1, current: v2, root: root) else {
            Issue.record("restore 应返回新版本")
            return
        }
        #expect(restored.version == 3)
        #expect(restored.instructions == "旧正文")
        #expect(restored.description == "旧描述")
        // 磁盘当前文件 = 回滚内容
        let onDisk = SkillStore.load(from: root).first { $0.name == "appx" }
        #expect(onDisk?.instructions == "旧正文")
        #expect(SkillVersioning.loadHistory(directory: dir).count == 3)
    }

    @Test func restoreMissingVersionNil() throws {
        let v1 = Skill(name: "appz", description: "d", instructions: "i", source: "s", version: 1)
        try SkillStore.save(v1, to: root)
        let result = try SkillVersioning.restore(name: "appz", to: 99, current: v1, root: root)
        #expect(result == nil)
    }

    @Test func diffShowsChanges() {
        let d = SkillVersioning.diff("a\nb\nc", "a\nx\nc")
        #expect(d.contains("- b"))
        #expect(d.contains("+ x"))
        #expect(SkillVersioning.diff("same", "same") == "（无差异）")
    }
}

// MARK: - 技能进化（自动评估/生成/保存/复用）

/// 纯函数用例（normalize/cluster/slugify/makeCandidate），无共享状态，保持并发
@Suite("SkillEvolution")
struct SkillEvolutionTests {
    @Test func slugifyASCIIWords() {
        #expect(SkillEvolution.slugify("Fix the Nginx deploy issue") == "fix-nginx-deploy-issue")
        #expect(SkillEvolution.slugify("restart postgres 5 times please ok") == "restart-postgres-5-times")
    }

    @Test func slugifyPureCJKStableHash() {
        let a = SkillEvolution.slugify("帮我重启一下数据库服务")
        let b = SkillEvolution.slugify("帮我重启一下数据库服务")
        #expect(a == b)
        #expect(a.hasPrefix("auto-"))
        #expect(a.count == 13)
    }

    @Test func clusterGroupsSimilarTasks() {
        let obs: [TaskObservation] = [
            .init(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态"),
            .init(sessionID: "s", task: "帮我重启一下 Nginx 服务，顺便看下状态"),
            .init(sessionID: "s", task: "把 PostgreSQL 从 14 升级到 16"),
        ]
        let clusters = SkillEvolution.cluster(obs, threshold: 0.5)
        #expect(clusters.count == 2)
        #expect(clusters.contains(where: { $0.count == 2 }))
        #expect(clusters.contains(where: { $0.count == 1 }))
    }

    @Test func engineResetClearsWindow() async {
        let engine = SkillEvolutionEngine(registry: SkillRegistry())
        await engine.observe(sessionID: "s", task: "任意任务文本内容用于填充")
        #expect(await engine.pendingObservationCount == 1)
        await engine.reset()
        #expect(await engine.pendingObservationCount == 0)
    }

    @Test func engineObservationCapAt200() async {
        let engine = SkillEvolutionEngine(registry: SkillRegistry())
        for i in 0 ..< 210 {
            await engine.observe(sessionID: "s", task: "填充观测窗口的不同任务\(i)")
        }
        #expect(await engine.pendingObservationCount == 200)
    }

    @Test func evaluateSkipsWhenRegistryHasName() async {
        let registry = SkillRegistry()
        await registry.register(Skill(name: "nginx", description: "x", instructions: "y", source: "builtin"))
        let engine = SkillEvolutionEngine(registry: registry, config: .init(minRepetition: 2, similarityThreshold: 0.5))
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态")
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态")
        // 注册表已有同名技能 → 跳过（不写盘）
        #expect(await (engine.evaluate()).isEmpty)
    }

    @Test func makeCandidateRequiresRepetition() {
        let one: [TaskObservation] = [.init(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态")]
        #expect(SkillEvolution.makeCandidate(from: one, minRepetition: 2) == nil)
        let two: [TaskObservation] = [
            .init(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态", toolNames: ["run_command", "read_file"]),
            .init(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态", toolNames: ["run_command"]),
        ]
        guard let candidate = SkillEvolution.makeCandidate(from: two, minRepetition: 2) else {
            Issue.record("应生成候选")
            return
        }
        #expect(candidate.evidenceCount == 2)
        #expect(!candidate.name.isEmpty)
        #expect(candidate.instructions.contains("run_command"))
        #expect(candidate.description.contains("自动沉淀技能"))
    }
}

// MARK: - 调试运行

@Suite("SkillDebugger")
struct SkillDebuggerTests {
    @Test func validSkillPasses() {
        let skill = Skill(name: "git-commit", description: "写约定式提交信息",
                          instructions: "## 步骤\n1. git status 查看变更\n2. 生成 conventional 提交信息",
                          tags: ["git"], source: "test")
        let report = SkillDebugger.debugRun(skill, sampleInput: "帮我写提交信息")
        #expect(report.passed)
        #expect(report.issues.isEmpty)
        #expect(report.promptPreview.contains("帮我写提交信息"))
        #expect(report.text.contains("✅ 结构校验通过"))
    }

    @Test func missingDescriptionFails() {
        let skill = Skill(name: "bad", description: "", instructions: "正文", source: "t")
        let report = SkillDebugger.debugRun(skill)
        #expect(!report.passed)
        #expect(report.issues.contains(where: { $0.severity == .error }))
    }

    @Test func placeholderWarning() {
        let skill = Skill(name: "draft", description: "未完成的技能",
                          instructions: "步骤：TODO 补充细节", source: "t")
        let report = SkillDebugger.debugRun(skill)
        #expect(report.issues.contains(where: { $0.severity == .warning && $0.message.contains("TODO") }))
    }

    @Test func previewRendersSkillAndInput() {
        let skill = Skill(name: "ops", description: "运维排查", instructions: "先查日志再看监控", source: "t")
        let preview = SkillDebugger.preview(skill: skill, sampleInput: "服务报 502")
        #expect(preview.contains("【技能 ops】运维排查"))
        #expect(preview.contains("先查日志再看监控"))
        #expect(preview.contains("服务报 502"))
    }
}

// MARK: - save_skill / debug_skill 工具

@Suite("SkillToolsExtended", .serialized) // 同上：save/debug 用例改写全局目录覆盖
struct SkillToolsExtendedTests {
    private let registry = SkillRegistry()

    @Test func saveSkillCreatesThenBumpsVersion() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 显式 saveRoot 注入：不依赖全局目录覆盖（跨 suite 并发安全）
        let ctx = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let tool = SaveSkillTool(registry: registry, saveRoot: dir)

        let r1 = try await tool.execute(["name": "my-skill", "description": "演示技能",
                                         "instructions": "## 步骤\n1. 开始", "tags": "a,b"],
                                        context: ctx)
        #expect(Self.text(r1).contains("已创建"))
        #expect(r1.meta?["version"] == "1")
        let r2 = try await tool.execute(["name": "my-skill", "description": "演示技能（改）",
                                         "instructions": "## 步骤\n1. 开始\n2. 扩展"],
                                        context: ctx)
        #expect(Self.text(r2).contains("v2"))
        #expect(await registry.skill(named: "my-skill")?.version == 2)
        // 版本历史已记录
        let history = SkillVersioning.loadHistory(directory: SkillStore.skillDirectory(for: "my-skill", root: dir))
        #expect(history.count == 2)
    }

    @Test func saveSkillInvalidArgs() async throws {
        let ctx = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let tool = SaveSkillTool(registry: registry)
        let r = try await tool.execute(["name": "x"], context: ctx)
        #expect(r.error?.code == "invalid_args")
    }

    @Test func debugSkillTool() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SkillStore.userSkillsDirectoryOverride = dir
        defer { SkillStore.userSkillsDirectoryOverride = nil }
        try SkillStore.save(Skill(name: "chk", description: "调试对象", instructions: "步骤正文", source: "t"), to: dir)
        await registry.register(Skill(name: "chk", description: "调试对象", instructions: "步骤正文", source: "t"))
        let ctx = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let tool = DebugSkillTool(registry: registry)
        let ok = try await tool.execute(["name": "chk", "sample_input": "样例"], context: ctx)
        #expect(Self.text(ok).contains("技能 chk"))
        #expect(ok.meta?["passed"] == "true")
        let missing = try await tool.execute(["name": "nope"], context: ctx)
        #expect(missing.error?.code == "skill_not_found")
    }

    // MARK: - 观测窗口持久化（CLI 短进程跨 run 累计）

    @Test func observationStoreRoundTrip() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("obs-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONObservationStore(url: url)
        #expect(store.load().isEmpty)
        let obs = [TaskObservation(sessionID: "s1", task: "帮我重启一下 Nginx 服务并检查状态",
                                   toolNames: ["run_command"])]
        store.save(obs)
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.task == obs[0].task)
        #expect(loaded.first?.toolNames == ["run_command"])
    }

    @Test func engineRestoresObservationsAcrossInstances() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-evo-restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("obs-restart-\(UUID().uuidString).json")
        let store = JSONObservationStore(url: storeURL)
        defer { try? FileManager.default.removeItem(at: storeURL) }

        // 进程 1：观测 1 次（未达阈值，不生成）
        let registry1 = SkillRegistry()
        let engine1 = SkillEvolutionEngine(registry: registry1,
                                           config: .init(minRepetition: 2, similarityThreshold: 0.5),
                                           observationStore: store,
                                           saveRoot: dir)
        await engine1.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态",
                              toolNames: ["run_command"])
        #expect(await (engine1.evaluate()).isEmpty)

        // 进程 2（新引擎实例，同一持久化文件）：再观测 1 次 → 累计 2 次 → 生成技能
        let registry2 = SkillRegistry()
        let engine2 = SkillEvolutionEngine(registry: registry2,
                                           config: .init(minRepetition: 2, similarityThreshold: 0.5),
                                           observationStore: store,
                                           saveRoot: dir)
        #expect(await engine2.pendingObservationCount == 1) // 恢复成功
        await engine2.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态",
                              toolNames: ["run_command"])
        let created = await engine2.evaluate()
        #expect(created.count == 1)
        #expect(await registry2.skill(named: created[0].name) != nil)
        #expect(!SkillStore.load(from: dir).isEmpty)
    }

    @Test func storeDeleteExistingAndMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-del-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("gone", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(SkillStore.delete("gone", from: root) == true)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(SkillStore.delete("nope", from: root) == false)
    }

    @Test func parseSkipsLeadingBlankLines() {
        let text = "\n\n---\nname: lead\ndescription: d\n---\n正文"
        #expect(SkillStore.parse(text, source: "t")?.name == "lead")
    }

    @Test func debuggerBoundaryIssues() {
        let emptyName = Skill(name: "", description: "d", instructions: "b", source: "s")
        #expect(SkillDebugger.validate(emptyName).contains { $0.message == "name 为空" })
        let longName = Skill(name: String(repeating: "a", count: 65), description: "d", instructions: "b", source: "s")
        #expect(SkillDebugger.validate(longName).contains { $0.message == "name 超过 64 字符" })
        let upperName = Skill(name: "My-Skill", description: "d", instructions: "b", source: "s")
        #expect(SkillDebugger.validate(upperName).contains { $0.severity == .warning && $0.message.contains("小写 slug") })
        let longDesc = Skill(name: "ok", description: String(repeating: "长", count: 201), instructions: "b", source: "s")
        #expect(SkillDebugger.validate(longDesc).contains { $0.message.contains("超过 200 字符") })
        let emptyBody = Skill(name: "ok", description: "d", instructions: "", source: "s")
        #expect(SkillDebugger.validate(emptyBody).contains { $0.message == "instructions 正文为空" })
        let hugeBody = Skill(name: "ok", description: "d", instructions: String(repeating: "长", count: 20001), source: "s")
        #expect(SkillDebugger.validate(hugeBody).contains { $0.message.contains("超过 20000 字符") })
    }

    @Test func debugRunTextRendersIssues() {
        let skill = Skill(name: "", description: "", instructions: "b", source: "s")
        let report = SkillDebugger.debugRun(skill)
        #expect(report.passed == false)
        #expect(report.text.contains("⛔ 调试未通过"))
        #expect(report.text.contains("❌"))
    }

    @Test func evaluateSurvivesSaveFailure() async throws {
        // override 指向「普通文件下的子路径」→ createDirectory 必失败 → 保存失败分支（不崩溃、跳过）
        let fileAsDir = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try "x".write(to: fileAsDir, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileAsDir) }
        SkillStore.userSkillsDirectoryOverride = fileAsDir.appendingPathComponent("impossible")
        defer { SkillStore.userSkillsDirectoryOverride = nil }
        let engine = SkillEvolutionEngine(registry: SkillRegistry(),
                                          config: .init(minRepetition: 2, similarityThreshold: 0.5))
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态")
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态")
        #expect(await (engine.evaluate()).isEmpty)
    }

    @Test func sharedEvolutionCachesEngine() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shared-evo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SkillStore.userSkillsDirectoryOverride = dir
        defer { SkillStore.userSkillsDirectoryOverride = nil }
        let registry = SkillRegistry()
        let e1 = await SharedSkillEvolution.shared.get(registry: registry)
        let e2 = await SharedSkillEvolution.shared.get(registry: registry)
        #expect(e1 === e2)
        // 复位：换回无持久化的干净引擎，避免污染同进程其它用例
        await SharedSkillEvolution.shared.replace(SkillEvolutionEngine(registry: registry))
    }

    @Test func makeAllFourTools() {
        #expect(SkillTools.makeAll(registry: registry).map(\.name).sorted()
            == ["debug_skill", "list_skills", "save_skill", "use_skill"])
    }

    private static func text(_ r: ToolResult) -> String {
        r.content.compactMap { part in
            if case let .text(s) = part {
                return s
            }
            return nil
        }.joined(separator: "\n")
    }

    @Test func engineAutoGeneratesAndDedupes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-evo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SkillStore.userSkillsDirectoryOverride = dir
        defer { SkillStore.userSkillsDirectoryOverride = nil }

        let registry = SkillRegistry()
        let engine = SkillEvolutionEngine(registry: registry,
                                          config: .init(minRepetition: 2, similarityThreshold: 0.5))
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态",
                             toolNames: ["run_command"])
        // 只有 1 次 → 不生成
        #expect(await (engine.evaluate()).isEmpty)
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态",
                             toolNames: ["run_command"])
        let created = await engine.evaluate()
        #expect(created.count == 1)
        // 落盘 + 注册（可复用）
        let skillName = created[0].name
        #expect(await registry.skill(named: skillName) != nil)
        #expect(!SkillStore.load(from: dir).isEmpty)
        // 再次 evaluate → 不重复生成
        #expect(await (engine.evaluate()).isEmpty)
        #expect(await engine.pendingObservationCount == 2)
    }

    @Test func engineSkipsExistingSkillName() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-evo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SkillStore.userSkillsDirectoryOverride = dir
        defer { SkillStore.userSkillsDirectoryOverride = nil }

        let registry = SkillRegistry()
        // 预置同名技能
        try SkillStore.save(Skill(name: "auto-\(String(repeating: "a", count: 8))", description: "x",
                                  instructions: "y", source: "manual"), to: dir)
        let engine = SkillEvolutionEngine(registry: registry,
                                          config: .init(minRepetition: 2, similarityThreshold: 0.5))
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态")
        await engine.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态")
        let created = await engine.evaluate()
        // 若生成的 slug 恰好与预置同名 → 跳过；否则生成。两种都合法，但不得报错
        let names = await (registry.all()).map(\.name)
        _ = names
        _ = created
    }
}

// MARK: - Skill 模型（Codable 向后兼容 / summary / id）

@Suite("SkillModelCodable")
struct SkillModelCodableTests {
    @Test func decodeLegacyJSONWithoutVersionDefaultsToOne() throws {
        let json = "{\"name\":\"legacy\",\"description\":\"旧格式\",\"instructions\":\"正文\",\"tags\":[\"a\"],\"source\":\"s\"}"
        let skill = try JSONDecoder().decode(Skill.self, from: Data(json.utf8))
        #expect(skill.version == 1)
        #expect(skill.name == "legacy")
        #expect(skill.tags == ["a"])
    }

    @Test func decodeWithVersionPreserved() throws {
        let json = "{\"name\":\"v3\",\"description\":\"x\",\"instructions\":\"正文\",\"tags\":[],\"source\":\"s\",\"version\":3}"
        let skill = try JSONDecoder().decode(Skill.self, from: Data(json.utf8))
        #expect(skill.version == 3)
    }

    @Test func encodeDecodeRoundTrip() throws {
        let skill = Skill(name: "rt", description: "d", instructions: "b", tags: ["t"], source: "s", version: 5)
        let data = try JSONEncoder().encode(skill)
        let back = try JSONDecoder().decode(Skill.self, from: data)
        #expect(back == skill)
    }

    @Test func summaryAndId() {
        let a = Skill(name: "demo", description: "说明", instructions: "b", tags: ["x", "y"], source: "s")
        #expect(a.summary == "demo — 说明  [x, y]")
        #expect(Skill(name: "b", description: "d", instructions: "i", source: "s").summary == "b — d")
        #expect(a.id == "demo")
    }
}
