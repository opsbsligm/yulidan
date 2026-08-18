import Foundation

// MARK: - 模型档案

/// 工具调用风格（不同服务商/模型差异）
public enum ToolCallStyle: String, Sendable, Codable {
    /// 原生 function calling（OpenAI / DeepSeek / Ollama 等）
    case native
    /// 无原生工具调用，需在提示词中约定围栏 JSON 格式
    case jsonFenced
    /// 不支持工具调用
    case none
}

/// 模型档案：用于提示词自动适配的模型元信息
public struct ModelProfile: Sendable, Codable, Hashable {
    /// 模型族（openai / deepseek / anthropic / local / generic）
    public let family: String
    /// 上下文窗口（token 估算）
    public let contextWindow: Int
    public let toolCallStyle: ToolCallStyle
    /// 最大输出 token（0 表示不限）
    public let maxOutputTokens: Int
    /// 模型专属提示注意事项（追加为 "模型说明" 段落）
    public let promptNotes: [String]

    public init(
        family: String,
        contextWindow: Int,
        toolCallStyle: ToolCallStyle,
        maxOutputTokens: Int = 0,
        promptNotes: [String] = []
    ) {
        self.family = family
        self.contextWindow = contextWindow
        self.toolCallStyle = toolCallStyle
        self.maxOutputTokens = maxOutputTokens
        self.promptNotes = promptNotes
    }
}

// MARK: - 档案目录

/// 内置模型档案目录：按模型名前缀匹配
public enum ModelProfileCatalog {
    private struct Rule {
        let prefix: [String]
        let profile: ModelProfile
    }

    private static let rules: [Rule] = [
        Rule(prefix: ["deepseek"], profile: ModelProfile(
            family: "deepseek", contextWindow: 65536, toolCallStyle: .native, maxOutputTokens: 8192,
            promptNotes: ["DeepSeek 系列对中文系统提示词理解良好，保持指令简洁直接。"]
        )),
        Rule(prefix: ["gpt", "o1", "o3", "chatgpt"], profile: ModelProfile(
            family: "openai", contextWindow: 128_000, toolCallStyle: .native, maxOutputTokens: 16384,
            promptNotes: []
        )),
        Rule(prefix: ["claude", "anthropic"], profile: ModelProfile(
            family: "anthropic", contextWindow: 200_000, toolCallStyle: .native, maxOutputTokens: 8192,
            promptNotes: ["Anthropic 模型建议将硬性约束放在提示词靠前位置。"]
        )),
        Rule(prefix: ["llama", "mistral", "qwen2.5"], profile: ModelProfile(
            family: "local", contextWindow: 32768, toolCallStyle: .native, maxOutputTokens: 4096,
            promptNotes: ["本地模型能力有限：优先使用简短提示词，复杂任务请拆小步骤。"]
        )),
        // qwen 云模型（需排在 qwen2.5 本地规则之后，更具体的前缀优先）
        Rule(prefix: ["qwen"], profile: ModelProfile(
            family: "qwen", contextWindow: 32768, toolCallStyle: .native, maxOutputTokens: 8192,
            promptNotes: []
        )),
    ]

    static let fallback = ModelProfile(family: "generic", contextWindow: 8192, toolCallStyle: .native)

    /// 按模型名匹配档案（前缀不区分大小写）；未知模型返回 generic 档案
    public static func profile(for model: String) -> ModelProfile {
        let lowered = model.lowercased()
        for rule in rules where rule.prefix.contains(where: { lowered.hasPrefix($0) }) {
            return rule.profile
        }
        return fallback
    }
}
