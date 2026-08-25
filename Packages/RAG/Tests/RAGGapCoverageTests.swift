import Foundation
import RAG
import Session
import Testing
import Tools

// MARK: - 覆盖审计轮 7：RAG 包薄弱分支（加载器兜底 / 空文档文案 / HARNESS_HOME / 引擎替换 / 过滤命中）

@Suite("RAG Gap Coverage")
struct RAGGapCoverageTests {
    private var context: ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    // MARK: DocumentLoader 兜底分支

    @Test("extractJSONTexts 非法 JSON 回退原始文本 / 非 UTF-8 回退空串")
    func extractJSONTextsFallsBackToRawText() {
        #expect(DocumentLoader.extractJSONTexts(Data("not json at all".utf8)) == "not json at all")
        let binary = Data([0xFF, 0xFE, 0x00, 0x01])
        #expect(DocumentLoader.extractJSONTexts(binary).isEmpty)
    }

    @Test("extractJSONTexts 跳过 null（default 分支）与纯空白字符串")
    func extractJSONTextsSkipsNullAndBlankStrings() {
        let json = #"{"a": null, "b": "   ", "c": 42, "d": [null, "ok"]}"#
        #expect(DocumentLoader.extractJSONTexts(Data(json.utf8)) == "c: 42\nd: ok")
    }

    // MARK: KnowledgeTools 空文档

    @Test("add_knowledge 空文档 → 「文档为空或无有效文本」")
    func addKnowledgeEmptyDocumentMessage() async throws {
        let engine = RAGEngine(store: VectorStore())
        let tool = KnowledgeAddTool(engine: engine)
        let emptyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag-gap-empty-\(UUID().uuidString).txt")
        try Data().write(to: emptyFile)
        defer { try? FileManager.default.removeItem(at: emptyFile) }
        let r = try await tool.execute(["path": emptyFile.path], context: context)
        let text = ToolResult.text(of: r)
        #expect(text.contains("文档为空或无有效文本"))
        #expect(text.contains(emptyFile.path))
    }

    // MARK: SharedRAGEngine 路径与替换

    @Test("HARNESS_HOME 环境变量覆盖默认索引路径")
    func sharedRAGEngineHarnessHomeOverride() {
        let oldPtr = getenv("HARNESS_HOME")
        let oldStr = oldPtr.map { String(cString: $0) }
        let tmp = NSTemporaryDirectory() + "rag-gap-home-\(UUID().uuidString)"
        setenv("HARNESS_HOME", tmp, 1)
        defer {
            if let oldStr {
                setenv("HARNESS_HOME", oldStr, 1)
            } else {
                unsetenv("HARNESS_HOME")
            }
        }
        let url = SharedRAGEngine.defaultIndexURL
        #expect(url.path.hasPrefix(tmp))
        #expect(url.path.hasSuffix("/.harness/rag/index.json"))
    }

    @Test("replace 注入自定义引擎后 get 返回同一实例")
    func sharedRAGEngineReplaceSwapsEngine() async {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag-gap-idx-\(UUID().uuidString)/index.json")
        let shared = SharedRAGEngine(indexURL: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent()) }

        let custom = RAGEngine(store: VectorStore())
        await shared.replace(custom)
        let got = await shared.get()
        #expect(got === custom, "replace 后 get 应返回注入实例")
    }

    // MARK: VectorStore 过滤命中

    @Test("元数据过滤命中（matches true 分支）与不命中对照")
    func vectorStoreMetadataFilterMatch() async {
        let store = VectorStore()
        let alpha = StoredChunk(id: "c1", documentID: "d1", index: 0, text: "量子纠缠 测试",
                                charStart: 0, charEnd: 8, source: "s.md", title: "t",
                                metadata: ["tag": "alpha"], vector: [0.1, 0.2, 0.3])
        let beta = StoredChunk(id: "c2", documentID: "d1", index: 1, text: "另一条目 对照",
                               charStart: 0, charEnd: 6, source: "s.md", title: "t",
                               metadata: ["tag": "beta"], vector: [0.4, 0.5, 0.6])
        await store.upsert([alpha, beta])

        let hit = await store.search(queryVector: [0.1, 0.2, 0.3], topK: 5, filter: ["tag": "alpha"])
        #expect(hit.map(\.id) == ["c1"])

        let miss = await store.search(queryVector: [0.1, 0.2, 0.3], topK: 5, filter: ["tag": "gamma"])
        #expect(miss.isEmpty)
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
