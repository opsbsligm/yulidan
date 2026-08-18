import Foundation
import RAG
import Session
import Testing
import Tools

/// KnowledgeTools 单元测试：参数校验 / 过滤解析 / 双模式入库 / 列表
@Suite("KnowledgeTools")
struct RAGKnowledgeToolsTests {
    private let engine = RAGEngine(store: VectorStore())
    private var context: ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    // MARK: search_knowledge

    @Test func searchEmptyQueryInvalidArgs() async throws {
        let tool = KnowledgeSearchTool(engine: engine)
        let r = try await tool.execute(["query": "  "], context: context)
        #expect(r.error?.code == "invalid_args")
    }

    @Test func searchNoResultsMessage() async throws {
        let tool = KnowledgeSearchTool(engine: engine)
        let r = try await tool.execute(["query": "不存在的罕见词 zzz"], context: context)
        #expect(r.error == nil)
        #expect(ToolResult.text(of: r).contains("未找到"))
    }

    @Test func searchFormatsResultsWithCitation() async throws {
        _ = await engine.ingestText("swift actor 并发隔离 模型", source: "c.md", title: "并发")
        let tool = KnowledgeSearchTool(engine: engine)
        let r = try await tool.execute(["query": "swift actor 并发", "top_k": "3"], context: context)
        let text = ToolResult.text(of: r)
        #expect(text.contains("找到 1 条相关内容"))
        #expect(text.contains("得分"))
        #expect(text.contains("c.md"))
        #expect(text.contains("块 1"))
        #expect(r.meta?["hits"] == "1")
    }

    @Test func searchTopKClamped() async throws {
        for i in 0 ..< 12 {
            _ = await engine.ingestText("条目编号\(i) 独立内容\(i) swift 检索", source: "d\(i).md")
        }
        let tool = KnowledgeSearchTool(engine: engine)
        let big = try await tool.execute(["query": "swift 检索 条目编号", "top_k": "99"], context: context)
        let small = try await tool.execute(["query": "swift 检索 条目编号", "top_k": "0"], context: context)
        #expect(ToolResult.text(of: big).contains("找到 10 条相关内容")) // top_k=99 → 截断到 10
        #expect(ToolResult.text(of: small).contains("找到 1 条相关内容"))
    }

    @Test func parseFilterVariants() {
        #expect(KnowledgeSearchTool.parseFilter(nil) == [:])
        #expect(KnowledgeSearchTool.parseFilter("") == [:])
        #expect(KnowledgeSearchTool.parseFilter("a=1, b = 2") == ["a": "1", "b": "2"])
        #expect(KnowledgeSearchTool.parseFilter("a=1,badpair,c=3") == ["a": "1", "c": "3"])
        #expect(KnowledgeSearchTool.parseFilter("=x,y") == [:]) // 空 key 丢弃、无 = 的片段忽略
        #expect(KnowledgeSearchTool.parseFilter("=x") == [:])
    }

    // MARK: add_knowledge

    @Test func addByPath() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rag-add-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("n.txt").path
        try "swift 知识库 入库 路径 模式".write(toFile: path, atomically: true, encoding: .utf8)
        let tool = KnowledgeAddTool(engine: engine)
        let r = try await tool.execute(["path": path], context: context)
        #expect(ToolResult.text(of: r).contains("已入库"))
        #expect(ToolResult.text(of: r).contains("切片"))
    }

    @Test func addByPathNotFound() async throws {
        let tool = KnowledgeAddTool(engine: engine)
        let r = try await tool.execute(["path": "/nonexistent/x.txt"], context: context)
        #expect(r.error?.code == "ingest_failed")
    }

    @Test func addByTextWithSourceAndTag() async throws {
        let tool = KnowledgeAddTool(engine: engine)
        let r = try await tool.execute(["text": "swift 记忆 长期 持久 内容", "source": "mem:ut", "tag": "mem"],
                                       context: context)
        #expect(ToolResult.text(of: r).contains("mem:ut"))
        let hits = await engine.retrieve(query: "swift 记忆 持久", options: .init(filter: ["tag": "mem"]))
        #expect(!hits.isEmpty)
    }

    @Test func addByTextFallbackSource() async throws {
        let tool = KnowledgeAddTool(engine: engine)
        let r = try await tool.execute(["text": "某条无来源文本"], context: context)
        #expect(ToolResult.text(of: r).hasPrefix("✅ 已入库 memory:"))
    }

    @Test func addMissingBothInvalidArgs() async throws {
        let tool = KnowledgeAddTool(engine: engine)
        let r = try await tool.execute(["tag": "x"], context: context)
        #expect(r.error?.code == "invalid_args")
    }

    // MARK: list_knowledge

    @Test func listEmpty() async throws {
        let tool = KnowledgeListTool(engine: engine)
        let r = try await tool.execute([:], context: context)
        #expect(ToolResult.text(of: r).contains("知识库为空"))
    }

    @Test func listDocuments() async throws {
        _ = await engine.ingestText("列表 验证 文本 一", source: "l1.md")
        let tool = KnowledgeListTool(engine: engine)
        let r = try await tool.execute([:], context: context)
        let text = ToolResult.text(of: r)
        #expect(text.contains("知识库共 1 个文档"))
        #expect(text.contains("1 个切片"))
    }

    @Test func makeAllReturnsThreeTools() {
        let tools = KnowledgeTools.makeAll(engine: engine)
        #expect(tools.map(\.name).sorted() == ["add_knowledge", "list_knowledge", "search_knowledge"])
    }
}

private extension ToolResult {
    /// 拼接全部 text 片段
    static func text(of result: ToolResult) -> String {
        result.content.compactMap { part in
            if case let .text(s) = part {
                return s
            }
            return nil
        }.joined(separator: "\n")
    }
}
