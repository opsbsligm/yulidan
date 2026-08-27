import Foundation
import ServiceContainer

public protocol LLMProvider: Sendable {
    var id: String { get }
    var supportedModels: [String] { get }
    /// 能力画像（决定 tools 下发 / reasoning 门控 / max_tokens 默认值等 wire 差异）
    var profile: ProviderProfile { get }
    func request(_ request: LLMRequest) async throws -> LLMResponse
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error>
}

/// 思考等级（用户配置维度；wire 为 OpenAI 兼容协议 `reasoning_effort` 字符串）。
/// - off = 不下发参数，跟随提供商/模型默认（官方文档：DeepSeek 默认 high；Ollama 仅思考模型生效）
/// - low / medium / high：OpenAI（o1/o3/o4/gpt-5 系）、DeepSeek（low/high/max，medium 映射 high）、Ollama（low/medium/high/max/none）均受理
public enum ThinkingLevel: String, Sendable, Codable, CaseIterable, Identifiable {
    case off, low, medium, high

    public var id: String {
        rawValue
    }

    /// wire 值（off → nil = 请求体不含 reasoning_effort 字段）
    public var wireValue: String? {
        self == .off ? nil : rawValue
    }

    public var displayName: String {
        switch self {
        case .off: "关（跟随提供商）"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    /// OpenAI 侧模型名门控：`reasoning_effort` 仅对推理模型受理，
    /// 向非推理模型（gpt-4o 等）下发会触发 400 → 命中下列前缀才允许下发
    public static func openAIApplies(toModel model: String) -> Bool {
        let m = model.lowercased()
        return ["o1", "o3", "o4", "gpt-5"].contains { m.contains($0) }
    }
}

public struct LLMRequest: Sendable {
    public let model: String
    public let messages: [Message]
    public let systemPrompt: String?
    public let tools: [ToolSchema]?
    public let maxTokens: Int?
    public let temperature: Double?
    /// 思考等级（nil / .off = 不下发 reasoning_effort）
    public let thinkingLevel: ThinkingLevel?
    /// 上下文窗口（Ollama options.num_ctx；nil = 不下发，仅本地模型使用）
    public let numCtx: Int?

    public init(model: String, messages: [Message], systemPrompt: String? = nil, tools: [ToolSchema]? = nil, maxTokens: Int? = nil, temperature: Double? = nil,
                thinkingLevel: ThinkingLevel? = nil, numCtx: Int? = nil) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.thinkingLevel = thinkingLevel
        self.numCtx = numCtx
    }

    /// 替换思考等级（OpenAI 模型名门控用）
    public func withThinkingLevel(_ level: ThinkingLevel?) -> LLMRequest {
        LLMRequest(model: model, messages: messages, systemPrompt: systemPrompt, tools: tools,
                   maxTokens: maxTokens, temperature: temperature, thinkingLevel: level, numCtx: numCtx)
    }
}

public struct LLMResponse: Sendable {
    public let id: String
    public let model: String
    public let content: [ContentBlock]
    public let usage: TokenUsage?
    public let toolCalls: [ToolCallBlock]?
    public let finishReason: FinishReason

    public init(id: String = UUID().uuidString, model: String, content: [ContentBlock], usage: TokenUsage? = nil, toolCalls: [ToolCallBlock]? = nil, finishReason: FinishReason) {
        self.id = id
        self.model = model
        self.content = content
        self.usage = usage
        self.toolCalls = toolCalls
        self.finishReason = finishReason
    }

    public enum FinishReason: String, Sendable {
        case stop, length, toolCalls, error
    }
}

public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public struct ToolSchema: Sendable {
    public let name: String
    public let description: String
    public let parameters: String // JSON string

    public init(name: String, description: String, parameters: String = "{}") {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// 默认连接测试（各适配器提供真实实现）
public extension LLMProvider {
    func checkConnection() async throws -> String {
        throw LLMError.networkError("该提供商不支持连接测试")
    }
}
