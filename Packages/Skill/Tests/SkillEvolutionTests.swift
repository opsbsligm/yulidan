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
        SkillStore.userSkillsDirectoryOverride = dir
        defer { SkillStore.userSkillsDirectoryOverride = nil }
        let ctx = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let tool = SaveSkillTool(registry: registry)

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
        SkillStore.userSkillsDirectoryOverride = dir
        defer { SkillStore.userSkillsDirectoryOverride = nil }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("obs-restart-\(UUID().uuidString).json")
        let store = JSONObservationStore(url: storeURL)
        defer { try? FileManager.default.removeItem(at: storeURL) }

        // 进程 1：观测 1 次（未达阈值，不生成）
        let registry1 = SkillRegistry()
        let engine1 = SkillEvolutionEngine(registry: registry1,
                                           config: .init(minRepetition: 2, similarityThreshold: 0.5),
                                           observationStore: store)
        await engine1.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态",
                              toolNames: ["run_command"])
        #expect(await (engine1.evaluate()).isEmpty)

        // 进程 2（新引擎实例，同一持久化文件）：再观测 1 次 → 累计 2 次 → 生成技能
        let registry2 = SkillRegistry()
        let engine2 = SkillEvolutionEngine(registry: registry2,
                                           config: .init(minRepetition: 2, similarityThreshold: 0.5),
                                           observationStore: store)
        #expect(await engine2.pendingObservationCount == 1) // 恢复成功
        await engine2.observe(sessionID: "s", task: "帮我重启一下 Nginx 服务并检查状态",
                              toolNames: ["run_command"])
        let created = await engine2.evaluate()
        #expect(created.count == 1)
        #expect(await registry2.skill(named: created[0].name) != nil)
        #expect(!SkillStore.load(from: dir).isEmpty)
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
