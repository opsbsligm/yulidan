import Foundation
import RAG
import Testing

/// VectorStore 单元测试：检索 / 过滤 / 删除 / 覆盖 / 持久化往返
@Suite("VectorStore")
struct RAGVectorStoreTests {
    private let vectorizer = HashingVectorizer()

    private func makeChunk(_ id: String, doc: String, index: Int, text: String,
                           metadata: [String: String] = [:]) -> StoredChunk {
        StoredChunk(id: id, documentID: doc, index: index, text: text,
                    charStart: 0, charEnd: text.count, source: "src:\(doc)",
                    title: doc, metadata: metadata, vector: vectorizer.embed(text))
    }

    @Test func upsertAndCounts() async {
        let store = VectorStore()
        // upsert 按「单次调用 = 一个文档」契约写入
        await store.upsert([
            makeChunk("c1", doc: "d1", index: 0, text: "swift actor"),
            makeChunk("c2", doc: "d1", index: 1, text: "并发 隔离"),
        ])
        await store.upsert([makeChunk("c3", doc: "d2", index: 0, text: "苹果 香蕉")])
        #expect(await store.documentIDs() == ["d1", "d2"])
        #expect(await store.count(documentID: "d1") == 2)
        #expect(await store.totalCount() == 3)
        #expect(await store.revision == 2)
    }

    @Test func upsertOverwritesSameDocument() async {
        let store = VectorStore()
        await store.upsert([makeChunk("a", doc: "d", index: 0, text: "旧内容")])
        await store.upsert([makeChunk("b", doc: "d", index: 0, text: "新内容")])
        #expect(await store.count(documentID: "d") == 1)
        let snap = await store.snapshot()
        #expect(snap[0].id == "b")
    }

    @Test func searchTopKByCosine() async {
        let store = VectorStore()
        await store.upsert([
            makeChunk("c1", doc: "d", index: 0, text: "swift actor 并发 隔离"),
            makeChunk("c2", doc: "d", index: 1, text: "番茄 炒蛋 菜谱"),
        ])
        let q = vectorizer.embed("swift actor 并发")
        let hits = await store.search(queryVector: q, topK: 2)
        // 余弦 ≤ 0 的无关块被过滤，只返回相关块
        #expect(hits.count == 1)
        #expect(hits[0].id == "c1")
    }

    @Test func searchRespectsFilter() async {
        let store = VectorStore()
        await store.upsert([
            makeChunk("c1", doc: "d", index: 0, text: "swift 工具", metadata: ["tag": "a"]),
            makeChunk("c2", doc: "d", index: 1, text: "swift 工具", metadata: ["tag": "b"]),
        ])
        let q = vectorizer.embed("swift 工具")
        let hits = await store.search(queryVector: q, topK: 5, filter: ["tag": "b"])
        #expect(hits.count == 1)
        #expect(hits[0].id == "c2")
    }

    @Test func removeAndClear() async {
        let store = VectorStore()
        await store.upsert([makeChunk("c1", doc: "d1", index: 0, text: "甲")])
        await store.upsert([makeChunk("c2", doc: "d2", index: 0, text: "乙")])
        await store.removeDocument("d1")
        #expect(await store.documentIDs() == ["d2"])
        #expect(await store.revision == 3)
        await store.clear()
        #expect(await store.totalCount() == 0)
        #expect(await store.revision == 4)
    }

    @Test func persistenceRoundTrip() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = VectorStore(fileURL: url)
        await store.upsert([
            makeChunk("c1", doc: "d1", index: 0, text: "swift actor 持久化", metadata: ["tag": "x"]),
        ])
        await store.save()

        let reloaded = VectorStore(fileURL: url)
        #expect(await reloaded.documentIDs() == ["d1"])
        #expect(await reloaded.count(documentID: "d1") == 1)
        #expect(await reloaded.revision == 1)
        let snap = await reloaded.snapshot()
        #expect(snap[0].metadata["tag"] == "x")
        #expect(snap[0].vector.elementsEqual(vectorizer.embed("swift actor 持久化")))
    }

    @Test func loadMissingFileIsEmpty() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rag-none-\(UUID().uuidString).json")
        let store = VectorStore(fileURL: url)
        #expect(await store.totalCount() == 0)
        #expect(await store.revision == 0)
    }
}

/// 元数据查询与过滤不匹配分支
@Suite("VectorStore metadata queries")
struct VectorStoreMetadataTests {
    private let vectorizer = HashingVectorizer()

    private func makeChunk(_ id: String, doc: String, index: Int, text: String,
                           metadata: [String: String] = [:]) -> StoredChunk {
        StoredChunk(id: id, documentID: doc, index: index, text: text,
                    charStart: 0, charEnd: text.count, source: "src:\(doc)",
                    title: doc, metadata: metadata, vector: vectorizer.embed(text))
    }

    @Test("documentIDs matchingMetadata returns sorted matches")
    func matchingMetadata() async {
        let store = VectorStore()
        await store.upsert([makeChunk("c1", doc: "d1", index: 0, text: "alpha",
                                      metadata: ["content_hash": "h1"])])
        await store.upsert([makeChunk("c2", doc: "d2", index: 0, text: "beta",
                                      metadata: ["content_hash": "h2"])])
        await store.upsert([makeChunk("c3", doc: "d3", index: 0, text: "gamma",
                                      metadata: ["content_hash": "h1"])])
        #expect(await store.documentIDs(matchingMetadata: "content_hash", value: "h1") == ["d1", "d3"])
        #expect(await store.documentIDs(matchingMetadata: "content_hash", value: "zzz") == [])
        #expect(await store.documentIDs(matchingMetadata: "no_such_key", value: "x") == [])
    }

    @Test("search with non-matching filter returns empty")
    func searchFilterMismatch() async {
        let store = VectorStore()
        await store.upsert([makeChunk("c1", doc: "d1", index: 0, text: "alpha beta",
                                      metadata: ["source": "s1"])])
        let hits = await store.search(queryVector: vectorizer.embed("alpha"), topK: 5,
                                      filter: ["source": "s2"])
        #expect(hits.isEmpty)
        let open = await store.search(queryVector: vectorizer.embed("alpha"), topK: 5)
        #expect(open.count == 1)
    }
}

@Suite("VectorStore filter positive path")
struct VectorStoreFilterPositiveTests {
    private let vectorizer = HashingVectorizer()

    private func makeChunk(_ id: String, doc: String, index: Int, text: String,
                           metadata: [String: String] = [:]) -> StoredChunk {
        StoredChunk(id: id, documentID: doc, index: index, text: text,
                    charStart: 0, charEnd: text.count, source: "src:\(doc)",
                    title: doc, metadata: metadata, vector: vectorizer.embed(text))
    }

    @Test("search with matching filter passes entries through")
    func searchFilterMatch() async {
        let store = VectorStore()
        await store.upsert([makeChunk("c1", doc: "d1", index: 0, text: "alpha beta",
                                      metadata: ["source": "s1"])])
        await store.upsert([makeChunk("c2", doc: "d2", index: 0, text: "alpha gamma",
                                      metadata: ["source": "s2"])])
        let hits = await store.search(queryVector: vectorizer.embed("alpha"), topK: 5,
                                      filter: ["source": "s1"])
        #expect(hits.count == 1)
        #expect(hits.first?.documentID == "d1")
    }
}
