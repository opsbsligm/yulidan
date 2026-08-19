import Foundation

// MARK: - JSONValue（通用 JSON 值，工具 schema / 工具参数解析复用）

/// 通用 JSON 值 — 用于把 JSON 字符串安全解析为可再编码的结构（如 tool 参数 schema、
/// Anthropic tool_use input），解析失败时可用 `emptyObject` 兜底。
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// 空对象兜底（工具 schema 解析失败时嵌入 wire 请求，保证 JSON 合法）
    public static let emptyObject = JSONValue.object([:])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析的 JSON 值")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(b):
            try container.encode(b)
        case let .number(n):
            try container.encode(n)
        case let .string(s):
            try container.encode(s)
        case let .array(a):
            try container.encode(a)
        case let .object(o):
            try container.encode(o)
        }
    }

    /// 从 JSON 字符串解析；失败返回 `emptyObject`
    public init(jsonString: String) {
        if let data = jsonString.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            self = value
        } else {
            self = .emptyObject
        }
    }

    /// 编码回 JSON 数据；失败返回空对象数据
    public func jsonData() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data("{}".utf8)
    }
}

// MARK: - 响应归一化器

/// 多模型响应归一化器（模块8 核心）— 把各提供商差异化输出收敛为统一内部协议：
/// 1. 工具参数 JSON 修复（围栏/散文前缀/尾逗号/截断括号，不可修复则原样保留）；
/// 2. reasoning 内容按画像门控合并为 .reasoning 块（置于文本前）；
/// 3. 空内容/空工具调用收敛为 nil。
public enum LLMResponseNormalizer {
    /// 修复工具调用参数 JSON 的常见缺陷：
    /// - ```json 代码围栏
    /// - JSON 前后的散文（取首个 { 到末个 }）
    /// - 尾随逗号（字符串外）
    /// - 截断导致的括号不平衡（仅补缺，不删多余）
    /// 修复后仍非法时原样返回，由上层 parseArguments 降级处理。
    public static func repairToolArguments(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return raw }

        // 1. 剥代码围栏
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
            // 去掉首行（``` 或 ```json）与末行围栏
            var bodyLines = lines
            if bodyLines.first?.hasPrefix("```") == true {
                bodyLines.removeFirst()
            }
            if bodyLines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
                bodyLines.removeLast()
            }
            text = bodyLines.joined(separator: "\n")
        }

        // 2. 截取首个 { 到末个 }（覆盖散文前缀/后缀；无闭合括号时截到末尾，交给补括号）
        guard let first = text.firstIndex(of: "{") else {
            // 无 JSON 对象结构，无法修复
            return raw
        }
        if let last = text.lastIndex(of: "}"), first < last {
            text = String(text[first ... last])
        } else {
            text = String(text.dropFirst(text.distance(from: text.startIndex, to: first)))
        }

        // 3. 去除字符串外的尾随逗号
        text = removeTrailingCommas(text)

        // 4. 补齐截断的括号（按栈逆序）
        text = balanceBrackets(text)

        // 5. 合法性校验：不可修则原样返回
        if isValidJSON(text) {
            return text
        }
        return raw
    }

    /// 归一化内容块：reasoning（画像门控）在前，文本在后
    public static func contentBlocks(result: CompletionResult, profile: ProviderProfile) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        if let reasoning = result.reasoning, !reasoning.isEmpty, profile.supportsReasoning {
            blocks.append(.reasoning(reasoning))
        }
        if !result.content.isEmpty {
            blocks.append(.text(result.content))
        }
        return blocks
    }

    /// 由归一化结果构造统一 LLMResponse
    public static func response(model: String, result: CompletionResult, profile: ProviderProfile) -> LLMResponse {
        let toolCalls = result.toolCalls.isEmpty
            ? nil
            : result.toolCalls.map { call in
                ToolCallBlock(id: call.id, name: call.name, arguments: repairToolArguments(call.arguments))
            }
        return LLMResponse(model: model,
                           content: contentBlocks(result: result, profile: profile),
                           usage: result.usage,
                           toolCalls: toolCalls,
                           finishReason: result.finishReason)
    }

    /// 对既有 LLMResponse 做工具参数修复（自定义 provider 的兜底归一化入口）
    public static func normalize(_ response: LLMResponse, profile _: ProviderProfile) -> LLMResponse {
        guard let calls = response.toolCalls, !calls.isEmpty else { return response }
        let repaired = calls.map {
            ToolCallBlock(id: $0.id, name: $0.name, arguments: repairToolArguments($0.arguments))
        }
        return LLMResponse(id: response.id,
                           model: response.model,
                           content: response.content,
                           usage: response.usage,
                           toolCalls: repaired,
                           finishReason: response.finishReason)
    }

    // MARK: - 私有工具

    private static func removeTrailingCommas(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inString {
                out.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                i += 1
                continue
            }
            switch ch {
            case "\"":
                inString = true
                out.append(ch)
            case ",":
                // 向后找第一个非空白字符，是 } 或 ] 则丢弃该逗号
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace {
                    j += 1
                }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" {
                    // 丢弃尾随逗号
                } else {
                    out.append(ch)
                }
            default:
                out.append(ch)
            }
            i += 1
        }
        return out
    }

    private static func balanceBrackets(_ text: String) -> String {
        let chars = Array(text)
        let inStringAt = Self.stringMask(chars)
        var stack: [Character] = []
        for (i, ch) in chars.enumerated() where !inStringAt[i] {
            switch ch {
            case "{":
                stack.append("}")
            case "[":
                stack.append("]")
            case "}", "]":
                if stack.last == ch {
                    stack.removeLast()
                }
            // 多余闭合括号不处理（无法安全修复）
            default:
                break
            }
        }
        // 末尾仍在字符串中说明引号不平衡 —— 不可修复
        if inStringAt.last == true {
            return text
        }
        return text + stack.reversed().map(String.init).joined()
    }

    /// 字符串状态掩码（true = 该字符处于双引号字符串内，考虑反斜杠转义）
    private static func stringMask(_ chars: [Character]) -> [Bool] {
        var mask = [Bool](repeating: false, count: chars.count)
        var inString = false
        var escaped = false
        for (i, ch) in chars.enumerated() {
            if inString {
                mask[i] = true
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else if ch == "\"" {
                inString = true
            }
        }
        return mask
    }

    private static func isValidJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
