import Foundation

// MARK: - 技能模型

/// Skill — 技能：一段可按需加载的指令文本（name/description 供 Agent 决策，instructions 为正文）
public struct Skill: Sendable, Hashable, Codable {
    /// 唯一标识（小写 slug）
    public var name: String
    /// 一句话描述（Agent 据此判断何时加载）
    public var description: String
    /// 技能正文（加载后注入给 Agent 的指令）
    public var instructions: String
    /// 标签（检索用）
    public var tags: [String]
    /// 来源（内置 / 用户目录路径）
    public var source: String

    public init(name: String, description: String, instructions: String, tags: [String] = [], source: String) {
        self.name = name
        self.description = description
        self.instructions = instructions
        self.tags = tags
        self.source = source
    }

    /// 展示用单行摘要
    public var summary: String {
        let tags = tags.isEmpty ? "" : "  [\(tags.joined(separator: ", "))]"
        return "\(name) — \(description)\(tags)"
    }
}

extension Skill: Identifiable {
    public var id: String {
        name
    }
}
