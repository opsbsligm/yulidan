import Foundation

// MARK: - OpenAI 兼容响应 DTO（文件级，避免局部类型嵌套过深；驼峰 + CodingKeys 对齐 wire 格式）

/// 助手消息内容（content 可空：纯工具调用响应时 content 为 null）
struct ChatMessageContentDTO: Decodable {
    let content: String?
    let reasoningContent: String?
    let toolCalls: [ChatToolCallDTO]?
    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

/// tool_calls 条目
struct ChatToolCallDTO: Decodable {
    let id: String?
    let type: String?
    let function: FunctionCall?
    struct FunctionCall: Decodable {
        let name: String?
        let arguments: String?
    }
}

/// choices 条目
struct ChatChoiceDTO: Decodable {
    let message: ChatMessageContentDTO
    let finishReason: String?
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

/// token 用量
struct ChatUsageDTO: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

/// chat/completions 响应
struct ChatCompletionRespDTO: Decodable {
    let choices: [ChatChoiceDTO]
    let usage: ChatUsageDTO?
}

// MARK: - OpenAI 兼容请求 DTO（模块内共享，仅 OpenAICompatChat 使用）

/// chat/completions 请求消息（支持 tools 下发的 assistant tool_calls 与 role:"tool" 结果）
struct ChatMessageDTO: Encodable {
    let role: String
    let content: String?
    let toolCalls: [ChatToolCallOutDTO]?
    let toolCallId: String?
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    init(role: String,
         content: String? = nil,
         toolCalls: [ChatToolCallOutDTO]? = nil,
         toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// 回传历史中的工具调用
struct ChatToolCallOutDTO: Encodable {
    let id: String
    let type: String
    let function: FunctionOut
    struct FunctionOut: Encodable {
        let name: String
        let arguments: String
    }
}

/// tools 下发条目：{type:"function", function:{name, description, parameters}}
struct ChatToolDTO: Encodable {
    let type: String
    let function: FunctionDef

    init(_ schema: ToolSchema) {
        type = "function"
        function = FunctionDef(name: schema.name,
                               description: schema.description,
                               parameters: JSONValue(jsonString: schema.parameters))
    }

    struct FunctionDef: Encodable {
        let name: String
        let description: String
        let parameters: JSONValue
    }
}

/// chat/completions 请求体
struct ChatRequestDTO: Encodable {
    var model: String
    var messages: [ChatMessageDTO]
    var tools: [ChatToolDTO]?
    var maxTokens: Int?
    var temperature: Double?
    var reasoningEffort: String?
    /// Ollama 专属 options（上下文窗口 num_ctx）；其余提供商忽略此字段
    var options: [String: Int]?
    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature, options
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }
}

/// SSE 增量 tool_call 片段
struct ChatDeltaToolCallDTO: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: DeltaFunction?
    struct DeltaFunction: Decodable {
        let name: String?
        let arguments: String?
    }
}

/// SSE 单条 data: 增量（message 可空：部分提供商存在 role-only 首块）
struct ChatDeltaDTO: Decodable {
    let choices: [ChatDeltaChoiceDTO]?
    let usage: ChatUsageDTO?
}

struct ChatDeltaChoiceDTO: Decodable {
    /// 真实 OpenAI wire 用 "delta"；早期桩/部分兼容实现用 "message"，两者皆收
    let delta: ChatDeltaMessageDTO?
    let message: ChatDeltaMessageDTO?
    let finishReason: String?
    enum CodingKeys: String, CodingKey {
        case delta, message
        case finishReason = "finish_reason"
    }

    var effectiveMessage: ChatDeltaMessageDTO? {
        delta ?? message
    }
}

struct ChatDeltaMessageDTO: Decodable {
    let role: String?
    let content: String?
    let reasoningContent: String?
    let toolCalls: [ChatDeltaToolCallDTO]?
    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}
