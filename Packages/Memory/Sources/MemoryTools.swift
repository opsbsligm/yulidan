import Foundation
import Tools

// MARK: - Agent 工具适配（记忆系统）

/// remember：显式写入长期记忆
public struct RememberTool: Tool {
    public let name = "remember"
    public let description = "把值得长期保留的信息写入长期记忆库（用户偏好/事实/决策/教训；自动做一致性校验与冲突取代）"
    public let parameterSchema = """
    {"type":"object","properties":{"content":{"type":"string","description":"要记住的内容（一句话）"},\
    "kind":{"type":"string","description":"fact|preference|decision|lesson|context，默认 fact"},\
    "topic":{"type":"string","description":"主题键（同主题新信息自动比对）"}},"required":["content"]}
    """
    public let requiredParameters = ["content"]

    private let engine: MemoryEngine

    public init(engine: MemoryEngine) {
        self.engine = engine
    }

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        let content = (args["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return ToolResult(content: [.text("错误：content 不能为空")],
                              error: ToolError(name: name, code: "invalid_args", message: "content 为空"))
        }
        let kind = MemoryKind(rawValue: (args["kind"] ?? "fact").lowercased()) ?? .fact
        let candidate = MemoryCandidate(content: content, kind: kind,
                                        topic: (args["topic"] ?? "").trimmingCharacters(in: .whitespaces),
                                        sourceSession: context.sessionID.rawValue.uuidString, origin: .manual)
        let decision = await engine.record(candidate)
        let message: String
        switch decision {
        case let .stored(id):
            message = "✅ 已写入长期记忆（\(id.prefix(8))…）"
        case let .merged(id):
            message = "✅ 与既有记忆一致，已合并强化（\(id.prefix(8))…）"
        case let .superseded(newID, oldID):
            message = "✅ 新信息取代旧记忆（旧 \(oldID.prefix(8))… → 新 \(newID.prefix(8))…）"
        case let .rejected(reason):
            return ToolResult(content: [.text("❌ 未写入：\(reason)")],
                              error: ToolError(name: name, code: "rejected", message: reason))
        }
        return ToolResult(content: [.text(message)], meta: ["decision": String(describing: decision)])
    }
}

/// recall_memory：召回相关长期记忆
public struct RecallMemoryTool: Tool {
    public let name = "recall_memory"
    public let description = "按查询召回相关长期记忆（偏好/事实/决策/教训），用于回答前先对齐已知信息"
    public let parameterSchema = """
    {"type":"object","properties":{"query":{"type":"string","description":"检索关键词/问题"},\
    "limit":{"type":"number","description":"返回条数，默认 5"}},"required":["query"]}
    """
    public let requiredParameters = ["query"]

    private let engine: MemoryEngine

    public init(engine: MemoryEngine) {
        self.engine = engine
    }

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let query = (args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ToolResult(content: [.text("错误：query 不能为空")],
                              error: ToolError(name: name, code: "invalid_args", message: "query 为空"))
        }
        let limit = Int(args["limit"] ?? "") ?? 5
        let items = await engine.recall(query: query, limit: min(10, max(1, limit)))
        guard !items.isEmpty else {
            return ToolResult(content: [.text("长期记忆中没有与「\(query)」相关的内容。")])
        }
        var lines = ["相关长期记忆（\(items.count) 条）："]
        for (i, item) in items.enumerated() {
            lines.append("\(i + 1). [\(item.kind.rawValue)/\(item.topic)] \(item.content)（意义度 \(String(format: "%.2f", item.significance))）")
        }
        return ToolResult(content: [.text(lines.joined(separator: "\n"))], meta: ["hits": "\(items.count)"])
    }
}

/// forget：删除长期记忆（按 id 或主题）
public struct ForgetTool: Tool {
    public let name = "forget"
    public let description = "从长期记忆库删除记忆：按 id（remember 返回的）或按主题清空"
    public let parameterSchema = """
    {"type":"object","properties":{"id":{"type":"string","description":"记忆 id（前 8 位即可）"},\
    "topic":{"type":"string","description":"主题键（与 id 二选一）"}}}
    """

    private let engine: MemoryEngine

    public init(engine: MemoryEngine) {
        self.engine = engine
    }

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let id = (args["id"] ?? "").trimmingCharacters(in: .whitespaces)
        let topic = (args["topic"] ?? "").trimmingCharacters(in: .whitespaces)
        if !id.isEmpty {
            let all = await engine.allForLookup()
            guard let item = all.first(where: { $0.id.hasPrefix(id) }) else {
                return ToolResult(content: [.text("未找到 id 前缀为 \(id) 的记忆")],
                                  error: ToolError(name: name, code: "not_found", message: "记忆不存在"))
            }
            _ = await engine.forget(id: item.id)
            return ToolResult(content: [.text("✅ 已删除记忆 \(item.id.prefix(8))…：\(item.content.prefix(40))")])
        }
        if !topic.isEmpty {
            let count = await engine.forget(topic: topic)
            return count > 0
                ? ToolResult(content: [.text("✅ 已删除主题「\(topic)」下 \(count) 条记忆")])
                : ToolResult(content: [.text("主题「\(topic)」下没有活跃记忆")],
                             error: ToolError(name: name, code: "not_found", message: "主题无记忆"))
        }
        return ToolResult(content: [.text("错误：需提供 id 或 topic")],
                          error: ToolError(name: name, code: "invalid_args", message: "缺少 id/topic"))
    }
}

public enum MemoryTools {
    /// 全套记忆工具
    public static func makeAll(engine: MemoryEngine) -> [any Tool] {
        [RememberTool(engine: engine), RecallMemoryTool(engine: engine), ForgetTool(engine: engine)]
    }
}
