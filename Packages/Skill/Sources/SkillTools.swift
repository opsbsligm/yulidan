import Foundation
import Tools

// MARK: - 技能工具（主 Agent 按需加载知识）

/// list_skills：列出全部可用技能（名称 + 描述），供 Agent 决策是否加载
public struct ListSkillsTool: Tool, Sendable {
    public let name = "list_skills"
    public let description = "列出全部可用技能（名称与描述）"
    public let parameterSchema = """
    {"type":"object","properties":{}}
    """

    private let registry: SkillRegistry

    public init(registry: SkillRegistry) {
        self.registry = registry
    }

    public func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let listing = await registry.promptListing()
        return ToolResult(content: [.text(listing.isEmpty ? "当前没有可用技能" : listing)])
    }
}

/// use_skill：按名称加载技能全文指令，Agent 随后遵循该指令执行
public struct UseSkillTool: Tool, Sendable {
    public let name = "use_skill"
    public let description = "按名称加载一个技能的完整指令（先 list_skills 查看可用技能）"
    public let parameterSchema = """
    {"type":"object","properties":{"name":{"type":"string","description":"技能名称（list_skills 中列出）"}},"required":["name"]}
    """

    public let requiredParameters = ["name"]

    private let registry: SkillRegistry

    public init(registry: SkillRegistry) {
        self.registry = registry
    }

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let raw = (args["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return ToolResult(content: [.text("缺少必填参数 name")],
                              error: ToolError(name: name, code: "invalid_args", message: "缺少必填参数 name"))
        }
        guard let skill = await registry.skill(named: raw) else {
            let names = await registry.all().map(\.name).joined(separator: ", ")
            let hint = names.isEmpty ? "当前没有可用技能" : "可用技能：\(names)"
            return ToolResult(content: [.text("技能「\(raw)」不存在。\(hint)")],
                              error: ToolError(name: name, code: "skill_not_found", message: "技能「\(raw)」不存在"))
        }
        return ToolResult(content: [.text("【技能 \(skill.name)】\(skill.description)\n\(skill.instructions)")])
    }
}

/// save_skill：把可复用任务流程保存为技能（同名自动版本 +1 并记录历史）
public struct SaveSkillTool: Tool {
    public let name = "save_skill"
    public let description = "把可复用的任务流程保存为技能（用户主动保存或 Agent 自动沉淀；同名技能自动升版本并保留历史）"
    public let parameterSchema = """
    {"type":"object","properties":{"name":{"type":"string","description":"技能名（小写 slug）"},\
    "description":{"type":"string","description":"一句话描述（Agent 据此判断何时使用）"},\
    "instructions":{"type":"string","description":"技能正文（步骤/注意事项，Markdown）"},\
    "tags":{"type":"string","description":"逗号分隔标签"}},"required":["name","description","instructions"]}
    """
    public let requiredParameters = ["name", "description", "instructions"]

    private let registry: SkillRegistry
    /// 技能保存根目录（nil = SkillStore 默认用户目录；测试可注入隔离目录）
    private let saveRoot: URL?

    public init(registry: SkillRegistry, saveRoot: URL? = nil) {
        self.registry = registry
        self.saveRoot = saveRoot
    }

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let name = (args["name"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let description = (args["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = (args["instructions"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !description.isEmpty, !instructions.isEmpty else {
            return ToolResult(content: [.text("错误：name/description/instructions 均不能为空")],
                              error: ToolError(name: name, code: "invalid_args", message: "缺少必填参数"))
        }
        let tags = (args["tags"] ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let existing = await registry.skill(named: name)
        var skill = Skill(name: name, description: description, instructions: instructions, tags: tags,
                          source: "manual",
                          version: (existing?.version ?? 0) + 1)
        do {
            let root = saveRoot ?? SkillStore.userSkillsDirectory
            let fileURL = try SkillStore.save(skill, to: root)
            skill.source = fileURL.path
            let directory = SkillStore.skillDirectory(for: skill.name, root: root)
            try? SkillVersioning.record(skill,
                                        note: existing == nil ? "新建" : "更新（覆盖旧版）",
                                        directory: directory)
        } catch {
            return ToolResult(content: [.text("❌ 保存失败：\(error.localizedDescription)")],
                              error: ToolError(name: name, code: "save_failed", message: error.localizedDescription))
        }
        _ = await registry.register(skill)
        let action = existing == nil ? "已创建" : "已更新（v\(skill.version)，旧版已存入历史）"
        return ToolResult(content: [.text("✅ 技能 \(name) \(action)")],
                          meta: ["name": name, "version": "\(skill.version)"])
    }
}

/// debug_skill：调试运行一个技能（结构校验 + 提示词预览，不消耗 LLM 调用）
public struct DebugSkillTool: Tool {
    public let name = "debug_skill"
    public let description = "调试运行一个技能：结构校验（name/描述/正文/占位符/往返一致性）+ 渲染 Agent 实际看到的提示词预览"
    public let parameterSchema = """
    {"type":"object","properties":{"name":{"type":"string","description":"技能名称"},\
    "sample_input":{"type":"string","description":"样例任务输入（渲染到预览中）"}},"required":["name"]}
    """
    public let requiredParameters = ["name"]

    private let registry: SkillRegistry

    public init(registry: SkillRegistry) {
        self.registry = registry
    }

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let raw = (args["name"] ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            return ToolResult(content: [.text("缺少必填参数 name")],
                              error: ToolError(name: name, code: "invalid_args", message: "缺少必填参数 name"))
        }
        guard let skill = await registry.skill(named: raw) else {
            let names = await registry.all().map(\.name).joined(separator: ", ")
            return ToolResult(content: [.text("技能「\(raw)」不存在。可用：\(names)")],
                              error: ToolError(name: name, code: "skill_not_found", message: "技能「\(raw)」不存在"))
        }
        let report = SkillDebugger.debugRun(skill, sampleInput: args["sample_input"] ?? "")
        let meta: [String: String] = ["passed": report.passed ? "true" : "false",
                                      "errors": "\(report.issues.count(where: { $0.severity == .error }))"]
        return ToolResult(content: [.text(report.text)], meta: meta)
    }
}

/// 全套技能工具
public enum SkillTools {
    public static func makeAll(registry: SkillRegistry) -> [any Tool] {
        [ListSkillsTool(registry: registry),
         UseSkillTool(registry: registry),
         SaveSkillTool(registry: registry),
         DebugSkillTool(registry: registry)]
    }
}
