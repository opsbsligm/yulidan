import Foundation
import Tools

// MARK: - Agent 工具适配

/// search_knowledge：检索本地 RAG 知识库
public struct KnowledgeSearchTool: Tool {
    public let name = "search_knowledge"
    public let description = "检索本地 RAG 知识库（已入库的文档切片），返回最相关片段与来源引用"
    public let parameterSchema = """
    {"type":"object","properties":{"query":{"type":"string","description":"检索关键词/问题"},\
    "top_k":{"type":"number","description":"返回条数，默认 5"},\
    "filter":{"type":"string","description":"元数据过滤，格式 k=v,k2=v2"}},"required":["query"]}
    """
    public let requiredParameters = ["query"]

    private let engine: RAGEngine

    public init(engine: RAGEngine) {
        self.engine = engine
    }

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let query = args["query"]?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !query.isEmpty else {
            return ToolResult(content: [.text("错误：query 不能为空")],
                              error: ToolError(name: name, code: "invalid_args", message: "query 为空"))
        }
        let topK = Int(args["top_k"] ?? "") ?? 5
        let filter = Self.parseFilter(args["filter"])
        let results = await engine.retrieve(query: query, options: .init(topK: min(10, max(1, topK)),
                                                                         filter: filter.isEmpty ? nil : filter))
        guard !results.isEmpty else {
            return ToolResult(content: [.text("知识库中未找到与「\(query)」相关的内容。")])
        }
        var lines = ["找到 \(results.count) 条相关内容："]
        for (i, r) in results.enumerated() {
            lines.append("\(i + 1). [得分 \(String(format: "%.3f", r.score))] \(r.citation)")
            let snippet = String(r.chunk.text.prefix(400))
            lines.append("   \(snippet)")
        }
        return ToolResult(content: [.text(lines.joined(separator: "\n"))],
                          meta: ["hits": "\(results.count)", "query": String(query.prefix(100))])
    }

    public static func parseFilter(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty else {
            return [:]
        }
        var out: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespaces)
            let v = kv[1].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty {
                out[k] = v
            }
        }
        return out
    }
}

/// add_knowledge：把文档/文本加入 RAG 知识库
public struct KnowledgeAddTool: Tool {
    public let name = "add_knowledge"
    public let description = "把文档文件（txt/md/html/json）或纯文本加入本地 RAG 知识库（支持 path 或 text）"
    public let parameterSchema = """
    {"type":"object","properties":{"path":{"type":"string","description":"文件路径"},\
    "text":{"type":"string","description":"纯文本内容（与 path 二选一）"},\
    "source":{"type":"string","description":"来源标识（text 模式必填）"},\
    "tag":{"type":"string","description":"元数据标签（用于 filter 过滤）"}}}
    """

    private let engine: RAGEngine

    public init(engine: RAGEngine) {
        self.engine = engine
    }

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let tag = args["tag"]?.trimmingCharacters(in: .whitespaces)
        let metadata: [String: String] = tag.map { ["tag": $0] } ?? [:]
        if let path = args["path"]?.trimmingCharacters(in: .whitespaces), !path.isEmpty {
            do {
                let count = try await engine.ingestPath(path, metadata: metadata)
                if count == 0 {
                    return ToolResult(content: [.text("文档为空或无有效文本：\(path)")])
                }
                return ToolResult(content: [.text("✅ 已入库 \(path)（\(count) 个切片）")],
                                  meta: ["chunks": "\(count)", "source": path])
            } catch {
                return ToolResult(content: [.text("❌ 入库失败：\(error.localizedDescription)")],
                                  error: ToolError(name: name, code: "ingest_failed", message: error.localizedDescription))
            }
        }
        if let text = args["text"], !text.isEmpty {
            let source = args["source"]?.trimmingCharacters(in: .whitespaces) ?? "memory:\(Date().timeIntervalSince1970)"
            let count = await engine.ingestText(text, source: source, metadata: metadata)
            return ToolResult(content: [.text("✅ 已入库 \(source)（\(count) 个切片）")],
                              meta: ["chunks": "\(count)", "source": source])
        }
        return ToolResult(content: [.text("错误：需提供 path 或 text")],
                          error: ToolError(name: name, code: "invalid_args", message: "缺少 path/text"))
    }
}

/// list_knowledge：查看已入库文档
public struct KnowledgeListTool: Tool {
    public let name = "list_knowledge"
    public let description = "列出 RAG 知识库中已入库的文档"
    public let parameterSchema = "{}"

    private let engine: RAGEngine

    public init(engine: RAGEngine) {
        self.engine = engine
    }

    public func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let ids = await engine.documentIDs()
        let (documents, chunks, _) = await engine.stats()
        guard !ids.isEmpty else {
            return ToolResult(content: [.text("知识库为空（用 add_knowledge 入库文档）")])
        }
        var lines = ["知识库共 \(documents) 个文档 / \(chunks) 个切片："]
        for id in ids {
            await lines.append("  • \(id.prefix(8))…（\(engine.count(documentID: id)) 个切片）")
        }
        return ToolResult(content: [.text(lines.joined(separator: "\n"))])
    }
}

public enum KnowledgeTools {
    /// 全套知识库工具
    public static func makeAll(engine: RAGEngine) -> [any Tool] {
        [KnowledgeSearchTool(engine: engine), KnowledgeAddTool(engine: engine), KnowledgeListTool(engine: engine)]
    }
}
