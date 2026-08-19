import Foundation
import RAG
import Session
import Testing
import Tools

/// 场景自测：走 ToolExecutor 完整生产链路（注册 → 必填参数校验 → 执行 → 错误归一化）
@Suite("RAGScenario — ToolExecutor 全链路")
struct RAGToolExecutorScenarioTests {
    private func makeContext() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    @Test func fullChainAddSearchListAndErrors() async throws {
        let registry = ToolRegistry()
        let engine = RAGEngine(store: VectorStore())
        for tool in KnowledgeTools.makeAll(engine: engine) {
            await registry.register(tool)
        }
        let executor = ToolExecutor()
        let ctx = makeContext()

        // 1) 真实文档文件入库（path 模式 + tag 元数据）
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rag-scenario-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("note.txt").path
        try "Swift 的 actor 并发模型提供内存安全。RAG 系统对入库文档做切片与向量化，检索时返回相关片段与来源引用。".write(
            toFile: path, atomically: true, encoding: .utf8
        )
        let addR = await executor.execute(ToolCall(name: "add_knowledge",
                                                   arguments: ["path": path, "tag": "sec"]),
                                          in: registry, context: ctx)
        #expect(addR.error == nil)
        #expect(Self.text(addR).contains("已入库"))

        // 2) 带 filter 的检索
        let searchR = await executor.execute(ToolCall(name: "search_knowledge",
                                                      arguments: ["query": "Swift actor 并发 检索", "filter": "tag=sec"]),
                                             in: registry, context: ctx)
        #expect(searchR.error == nil)
        #expect(Self.text(searchR).contains("找到 1 条相关内容"))
        #expect(Self.text(searchR).contains("note.txt"))

        // 3) 列表
        let listR = await executor.execute(ToolCall(name: "list_knowledge", arguments: [:]),
                                           in: registry, context: ctx)
        #expect(Self.text(listR).contains("知识库共 1 个文档"))

        // 4) 缺必填参数 → 执行器统一归一化 invalid_args（不进工具体）
        let badR = await executor.execute(ToolCall(name: "search_knowledge", arguments: [:]),
                                          in: registry, context: ctx)
        #expect(badR.error?.code == "invalid_args")

        // 5) 未注册工具 → unknown_tool
        let unknownR = await executor.execute(ToolCall(name: "no_such_tool", arguments: [:]),
                                              in: registry, context: ctx)
        #expect(unknownR.error?.code == "unknown_tool")
    }

    @Test func ingestSameFileTwiceDedupes() async throws {
        // 已知 P2：ingestPath 每次生成新文档 UUID，同文件重复入库不去重（内容重复但可移除）
        let registry = ToolRegistry()
        let engine = RAGEngine(store: VectorStore())
        for tool in KnowledgeTools.makeAll(engine: engine) {
            await registry.register(tool)
        }
        let executor = ToolExecutor()
        let ctx = makeContext()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rag-scenario-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("dup.txt").path
        try "重复入库测试 文本内容".write(toFile: path, atomically: true, encoding: .utf8)

        _ = await executor.execute(ToolCall(name: "add_knowledge", arguments: ["path": path]),
                                   in: registry, context: ctx)
        _ = await executor.execute(ToolCall(name: "add_knowledge", arguments: ["path": path]),
                                   in: registry, context: ctx)
        // 同路径二次入库：文档 id 不同（UUID）但内容相同 → 检索命中数不膨胀
        let searchR = await executor.execute(ToolCall(name: "search_knowledge", arguments: ["query": "重复入库测试"]),
                                             in: registry, context: ctx)
        // 去重（P2 闭环）：同路径二次 ingest → 同 source 覆盖，不产生重复块
        let docs = await engine.documentIDs()
        #expect(docs.count == 1)
        #expect(Self.text(searchR).contains("找到"))
        _ = docs
    }

    private static func text(_ r: ToolResult) -> String {
        r.content.compactMap { part in
            if case let .text(s) = part {
                return s
            }
            return nil
        }.joined(separator: "\n")
    }
}
