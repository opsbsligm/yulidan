import Foundation

/// 协议家族 — 决定 wire 格式（请求/响应/工具调用序列化）
public enum ProviderFamily: String, Sendable, Codable {
    /// OpenAI chat/completions 兼容协议（OpenAI / DeepSeek / Ollama / vLLM / LM Studio）
    case openAICompat
    /// Anthropic messages 协议
    case anthropic
}

/// 提供商能力画像 — 多模型归一层的核心配置：
/// 上层业务（AgentLoop / App）不感知具体厂商差异，仅依据画像决定能力门控与默认值。
public struct ProviderProfile: Sendable, Equatable {
    public let family: ProviderFamily
    /// 该提供商的 API 是否支持 function/tool calling
    public let supportsToolCalls: Bool
    /// 是否输出推理过程（reasoning_content / thinking 等），门控 .reasoning 内容块
    public let supportsReasoning: Bool
    /// 协议强制要求的 max_tokens 缺省值（如 Anthropic 必填 max_tokens）
    public let defaultMaxTokens: Int?

    public init(family: ProviderFamily,
                supportsToolCalls: Bool,
                supportsReasoning: Bool,
                defaultMaxTokens: Int? = nil) {
        self.family = family
        self.supportsToolCalls = supportsToolCalls
        self.supportsReasoning = supportsReasoning
        self.defaultMaxTokens = defaultMaxTokens
    }

    /// OpenAI：完整工具调用；o 系列推理不在本客户端范围内（reasoning 关）
    public static let openAI = ProviderProfile(family: .openAICompat,
                                               supportsToolCalls: true,
                                               supportsReasoning: false)
    /// DeepSeek：chat/reasoner 均走 OpenAI 兼容协议；reasoner 输出 reasoning_content
    public static let deepSeek = ProviderProfile(family: .openAICompat,
                                                 supportsToolCalls: true,
                                                 supportsReasoning: true)
    /// 本地 OpenAI 兼容服务（Ollama / vLLM / LM Studio）：
    /// 工具调用支持依赖具体引擎，默认关闭，避免上层误判能力
    public static let local = ProviderProfile(family: .openAICompat,
                                              supportsToolCalls: false,
                                              supportsReasoning: false)
    /// Anthropic：tools 必填 input_schema；max_tokens 为必填字段
    public static let anthropic = ProviderProfile(family: .anthropic,
                                                  supportsToolCalls: true,
                                                  supportsReasoning: false,
                                                  defaultMaxTokens: 4096)
}

public extension LLMProvider {
    /// 默认能力画像：面向 mock/脚本化 provider（单测桩），无真实 wire 能力。
    /// 真实适配器各自覆写。
    var profile: ProviderProfile {
        ProviderProfile.local
    }
}
