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
    /// 来源（内置 / 用户目录路径 / auto）
    public var source: String
    /// 版本号（更新 +1；版本管理用，旧数据缺失时按 1 解码）
    public var version: Int

    public init(name: String, description: String, instructions: String, tags: [String] = [], source: String,
                version: Int = 1) {
        self.name = name
        self.description = description
        self.instructions = instructions
        self.tags = tags
        self.source = source
        self.version = version
    }

    /// Codable 向后兼容：旧数据（无 version 字段）解码为 1
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        instructions = try c.decode(String.self, forKey: .instructions)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try c.decode(String.self, forKey: .source)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
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
