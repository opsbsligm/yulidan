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

public struct LLMRequest: Sendable {
    public let model: String
    public let messages: [Message]
    public let systemPrompt: String?
    public let tools: [ToolSchema]?
    public let maxTokens: Int?
    public let temperature: Double?

    public init(model: String, messages: [Message], systemPrompt: String? = nil, tools: [ToolSchema]? = nil, maxTokens: Int? = nil, temperature: Double? = nil) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.maxTokens = maxTokens
        self.temperature = temperature
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
