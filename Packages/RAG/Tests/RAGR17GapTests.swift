import Foundation
import RAG
import Session
import Testing
import Tools

// MARK: - 覆盖审计轮 17：RAG 残余兜底行（DocumentLoader 非 UTF-8 回退 / JSON 递归抽取 / VectorStore 兜底 / 工具参数兜底）

@Suite("RAG R17 Gap Coverage")
struct RAGR17GapTests {
    private let vectorizer = HashingVectorizer()

    private var context: ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-rag-r17-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: DocumentLoader 兜底分支

    /// ① 非 UTF-8 字节 .txt → utf8 解码失败 → isoLatin1 回退（外层 `??` thunk）
    @Test("DocumentLoader: 非 UTF-8 .txt → isoLatin1 回退")
    func txtNonUTF8FallsBackToLatin1() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("bad.txt")
        try Data([0xFF, 0xFE, 0x41]).write(to: url)
        let doc = try DocumentLoader.load(path: url.path)
        // isoLatin1：0xFF → ÿ，0xFE → þ，0x41 → A
        #expect(doc.text == "ÿþA")
    }

    /// ② 非 UTF-8 字节 .html → html 分支同样回退 isoLatin1（外层 `??` thunk）
    @Test("DocumentLoader: 非 UTF-8 .html → isoLatin1 回退")
    func htmlNonUTF8FallsBackToLatin1() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("bad.html")
        try Data([0xFF, 0xFF]).write(to: url)
        let doc = try DocumentLoader.load(path: url.path)
        #expect(doc.text == "ÿÿ")
    }

    /// ③ 嵌套 JSON → 递归抽取「键: 值」（String / NSNumber 两处 key.map 闭包）
    @Test("DocumentLoader: 嵌套 JSON 递归抽取键值对")
    func jsonNestedExtractsKeyValues() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested.json")
        try Data(#"{"a":{"b":"c","n":1}}"#.utf8).write(to: url)
        let doc = try DocumentLoader.load(path: url.path)
        #expect(doc.text.contains("b: c"))
        #expect(doc.text.contains("n: 1"))
    }

    // MARK: KnowledgeSearchTool 参数兜底

    /// ④ 缺 query → `?? ""` 兜底 → 空查询拒绝
    @Test("KnowledgeSearchTool: 缺 query → 空串兜底 + 拒绝")
    func searchToolMissingQuery() async throws {
        let store = VectorStore()
        let tool = KnowledgeSearchTool(engine: RAGEngine(store: store))
        let result = try await tool.execute([:], context: context)
        #expect(result.error?.code == "invalid_args")
    }

    // MARK: VectorStore 兜底分支

    /// ⑤ count 未知文档 → `?? 0`；snapshot 双排序闭包；filter 不匹配 → matches return false
    @Test("VectorStore: count 兜底 / snapshot 排序 / 元数据过滤")
    func vectorStoreFallbacks() async {
        let store = VectorStore()
        #expect(await store.count(documentID: "missing-doc") == 0)

        func chunk(_ id: String, doc: String, index: Int, text: String, tag: String) -> StoredChunk {
            StoredChunk(id: id, documentID: doc, index: index, text: text,
                        charStart: 0, charEnd: text.count, source: "src:\(doc)",
                        title: doc, metadata: ["tag": tag], vector: vectorizer.embed(text))
        }
        // 两次 upsert = 两个文档（单次调用 = 一个文档的契约）
        await store.upsert([
            chunk("a1", doc: "docA", index: 1, text: "alpha one", tag: "a"),
            chunk("a2", doc: "docA", index: 2, text: "alpha two", tag: "a"),
        ])
        await store.upsert([
            chunk("b1", doc: "docB", index: 1, text: "beta one", tag: "b"),
            chunk("b2", doc: "docB", index: 2, text: "beta two", tag: "b"),
        ])

        // 快照（排序闭包执行 ≥1 次）。
        // 生产代码奇特性（轮 17 实锤，记 P2）：排序比较器 `docID < docID' || index < index'`
        // 不是严格弱序（跨文档互判「小于」），跨文档顺序未定义；同文档内退化为 index 比较是良定的。
        let snap = await store.snapshot()
        #expect(Set(snap.map(\.id)) == Set(["a1", "a2", "b1", "b2"]))
        let byDoc = Dictionary(grouping: snap, by: \.documentID)
        #expect(byDoc["docA"]?.map(\.index) == [1, 2])
        #expect(byDoc["docB"]?.map(\.index) == [1, 2])

        // filter tag=b → docA 切片被 matches 拒绝（return false 分支）
        let hits = await store.search(queryVector: vectorizer.embed("beta one"), topK: 5, filter: ["tag": "b"])
        #expect(hits.allSatisfy { $0.metadata["tag"] == "b" })
        #expect(hits.contains { $0.id == "b1" })
    }
}
