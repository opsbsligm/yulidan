import Foundation
import Session
import Skill
import Testing
import Tools
import XCTest

// MARK: - SKILL.md 解析

@Suite("SkillStore.parse frontmatter 解析")
struct SkillParseTests {
    private let valid = """
    ---
    name: demo-skill
    description: 演示技能
    tags: a, b
    ---
    正文第一行
    正文第二行
    """

    @Test("正常 frontmatter：name/description/tags/正文")
    func parseValid() {
        let skill = SkillStore.parse(valid, source: "test")
        #expect(skill?.name == "demo-skill")
        #expect(skill?.description == "演示技能")
        #expect(skill?.tags == ["a", "b"])
        #expect(skill?.instructions == "正文第一行\n正文第二行")
        #expect(skill?.source == "test")
    }

    @Test("无 tags 字段：空数组")
    func parseWithoutTags() {
        let text = "---\nname: no-tags\ndescription: 无标签\n---\n正文"
        let skill = SkillStore.parse(text, source: "t")
        #expect(skill?.tags.isEmpty == true)
        #expect(skill?.instructions == "正文")
    }

    @Test("缺少 frontmatter 开头：nil")
    func parseMissingFrontmatter() {
        #expect(SkillStore.parse("直接正文，没有 frontmatter", source: "t") == nil)
    }

    @Test("frontmatter 未闭合：nil")
    func parseUnclosed() {
        let text = "---\nname: broken\ndescription: 未闭合\n正文"
        #expect(SkillStore.parse(text, source: "t") == nil)
    }

    @Test("缺少 name 或 name 为空：nil")
    func parseMissingName() {
        #expect(SkillStore.parse("---\ndescription: 没有 name\n---\n正文", source: "t") == nil)
        #expect(SkillStore.parse("---\nname: \ndescription: 空 name\n---\n正文", source: "t") == nil)
    }
}

// MARK: - 目录加载

final class SkillStoreLoadTests: XCTestCase {
    /// 每个测试实例独立临时目录（writeSkill 时按需创建）
    private var dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("skill-test-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeSkill(folder: String, content: String) throws {
        let folderURL = dir.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try content.write(to: folderURL.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func testLoadValidAndSkipInvalid() throws {
        try writeSkill(folder: "zzz-last", content: "---\nname: zzz-last\ndescription: 排序验证\n---\nB")
        try writeSkill(folder: "aaa-first", content: "---\nname: aaa-first\ndescription: 排序验证\n---\nA")
        try writeSkill(folder: "broken", content: "没有 frontmatter 的无效文件")
        // 非 md 文件忽略
        FileManager.default.createFile(atPath: dir.appendingPathComponent("notes.txt").path,
                                       contents: Data("x".utf8))
        let skills = SkillStore.load(from: dir)
        XCTAssertEqual(skills.map(\.name), ["aaa-first", "zzz-last"])
        XCTAssertEqual(skills.first?.instructions, "A")
    }

    func testLoadMissingDirectory() {
        let missing = dir.appendingPathComponent("not-exist")
        XCTAssertTrue(SkillStore.load(from: missing).isEmpty)
    }
}

// MARK: - 注册表

@Suite("SkillRegistry 注册/检索")
struct SkillRegistryTests {
    private func makeRegistry() async -> SkillRegistry {
        let registry = SkillRegistry()
        await registry.register(Skill(name: "git-commit", description: "写提交信息", instructions: "i1",
                                      tags: ["git"], source: "builtin"))
        await registry.register(Skill(name: "code-review", description: "评审清单", instructions: "i2",
                                      tags: ["review"], source: "builtin"))
        return registry
    }

    @Test("重名覆盖 + remove + all 排序", .serialized)
    func registerDedupeAndRemove() async {
        let registry = await makeRegistry()
        #expect(await registry.count == 2)
        let isNew = await registry.register(Skill(name: "git-commit", description: "覆盖后", instructions: "x",
                                                  tags: [], source: "user"))
        #expect(isNew == false)
        #expect(await registry.count == 2)
        #expect(await (registry.skill(named: "git-commit"))?.description == "覆盖后")
        #expect(await registry.remove("git-commit") != nil)
        #expect(await registry.all().map(\.name) == ["code-review"])
    }

    @Test("按 name/description/tags 检索；空查询返回全部")
    func search() async {
        let registry = await makeRegistry()
        #expect(await (registry.search("git")).map(\.name) == ["git-commit"])
        #expect(await (registry.search("评审")).map(\.name) == ["code-review"])
        #expect(await (registry.search("REVIEW")).map(\.name) == ["code-review"])
        #expect(await (registry.search("不存在的词")).isEmpty)
        #expect(await (registry.search("   ")).count == 2)
    }

    @Test("promptListing 每行 name — description")
    func promptListing() async {
        let registry = await makeRegistry()
        let listing = await registry.promptListing()
        #expect(listing.contains("- code-review — 评审清单"))
        #expect(listing.contains("- git-commit — 写提交信息"))
    }
}

// MARK: - 技能工具

final class SkillToolTests: XCTestCase {
    private func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private func registry(with skills: [Skill]) async -> SkillRegistry {
        let registry = SkillRegistry()
        for skill in skills {
            await registry.register(skill)
        }
        return registry
    }

    private let demo = Skill(name: "demo", description: "演示技能", instructions: "按步骤执行：1. 2. 3.",
                             tags: ["demo"], source: "test")

    func testUseSkillSuccess() async throws {
        let tool = await UseSkillTool(registry: registry(with: [demo]))
        let result = try await tool.execute(["name": "demo"], context: context())
        XCTAssertNil(result.error)
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        XCTAssertTrue(text.contains("按步骤执行：1. 2. 3."))
        XCTAssertTrue(text.contains("【技能 demo】"))
    }

    func testUseSkillNotFound() async throws {
        let tool = await UseSkillTool(registry: registry(with: [demo]))
        let result = try await tool.execute(["name": "不存在"], context: context())
        XCTAssertEqual(result.error?.code, "skill_not_found")
    }

    func testUseSkillMissingArg() async throws {
        let tool = await UseSkillTool(registry: registry(with: []))
        let result = try await tool.execute(["name": "  "], context: context())
        XCTAssertEqual(result.error?.code, "invalid_args")
    }

    func testListSkillsEmpty() async throws {
        let tool = await ListSkillsTool(registry: registry(with: []))
        let result = try await tool.execute([:], context: context())
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        XCTAssertEqual(text, "当前没有可用技能")
    }

    func testListSkillsNonEmpty() async throws {
        let tool = await ListSkillsTool(registry: registry(with: [demo]))
        let result = try await tool.execute([:], context: context())
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        XCTAssertTrue(text.contains("- demo — 演示技能"))
    }
}
