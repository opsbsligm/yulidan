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
