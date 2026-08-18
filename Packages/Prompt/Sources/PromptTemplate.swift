import Foundation

// MARK: - 模板

/// 角色模板：有序段落集合，支持版本快照
public struct PromptTemplate: Sendable, Codable, Hashable {
    /// 模板名（唯一标识，如 "agent" / "subagent"）
    public var name: String
    public var description: String
    public var sections: [PromptSection]
    /// 单调递增版本号（每次 update +1）
    public var version: Int
    public var updatedAt: Date
    /// 内置模板受保护（用户编辑产生新版本，不覆盖内置源）
    public var isBuiltIn: Bool

    public init(
        name: String,
        description: String = "",
        sections: [PromptSection],
        version: Int = 1,
        updatedAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.name = name
        self.description = description
        self.sections = sections
        self.version = version
        self.updatedAt = updatedAt
        self.isBuiltIn = isBuiltIn
    }

    /// 排序后的有效段落（priority 升序，跳过禁用）
    public var effectiveSections: [PromptSection] {
        sections.filter(\.enabled).sorted { $0.priority < $1.priority }
    }
}

// MARK: - 渲染上下文

/// 动态渲染上下文：标量变量 + 条件块
public struct PromptContext: Sendable {
    /// 标量变量：`{{var}}` 占位符替换
    public var variables: [String: String]
    /// 条件块：`{{#block}}...{{/block}}`，有内容则展开，否则整块移除
    public var blocks: [String: String]

    public init(variables: [String: String] = [:], blocks: [String: String] = [:]) {
        self.variables = variables
        self.blocks = blocks
    }

    public static let empty = PromptContext()
}
