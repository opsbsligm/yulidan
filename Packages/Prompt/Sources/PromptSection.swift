import Foundation

// MARK: - 段落类型

/// 提示词段落类型（编排的基本单元）
public enum PromptSectionKind: String, Sendable, Codable, CaseIterable {
    /// 角色定义
    case role
    /// 背景上下文（可动态注入：RAG 检索结果、长期记忆摘要等）
    case context
    /// 行为约束 / 规则
    case rules
    /// 工具使用说明
    case tools
    /// 输出格式要求
    case output
}

// MARK: - 段落

/// 提示词段落：一段带类型的模板文本，按 priority 升序参与编排
public struct PromptSection: Sendable, Hashable, Codable {
    public let kind: PromptSectionKind
    /// 段落标题（渲染为 `## 标题`；空标题则直接输出正文）
    public let title: String
    /// 模板正文，支持 `{{变量}}` 与 `{{#块名}}...{{/块名}}` 条件块
    public let template: String
    /// 排序优先级（越小越靠前）
    public let priority: Int
    public let enabled: Bool

    public init(
        kind: PromptSectionKind,
        title: String = "",
        template: String,
        priority: Int = 100,
        enabled: Bool = true
    ) {
        self.kind = kind
        self.title = title
        self.template = template
        self.priority = priority
        self.enabled = enabled
    }
}
