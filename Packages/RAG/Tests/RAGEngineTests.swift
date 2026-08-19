import Foundation
import RAG
import Testing

/// RAGEngine 端到端：入库 → 检索 → 重排 → 过滤 → 溯源 → 移除
@Suite("RAGEngine")
struct RAGEngineTests {
    private func makeEngine() -> RAGEngine {
        RAGEngine(store: VectorStore())
    }

    @Test func endToEndRetrievalRanking() async {
        let engine = makeEngine()
        await engine.ingestText("swift actor 模型提供并发隔离，杜绝数据竞争，是 Agent 框架的基石",
                                source: "concurrency.md", title: "并发模型")
        await engine.ingestText("番茄炒蛋：鸡蛋三只，番茄两个，先蛋后蛋，大火快炒出锅装盘",
                                source: "recipe.md", title: "菜谱")
        let hits = await engine.retrieve(query: "swift actor 并发 隔离")
        #expect(!hits.isEmpty)
        #expect(hits[0].source == "concurrency.md")
        #expect(hits[0].title == "并发模型")
        #expect(hits[0].termHits >= 3)
        for h in hits {
            #expect(h.score >= 0)
            #expect(h.score <= 1)
            // 重排分 = 余弦 + 0.3×词重叠，必然不小于召回余弦分
            #expect(h.score >= h.cosineScore - 0.0001)
        }
    }

    @Test func citationCarriesProvenance() async {
        let engine = makeEngine()
        _ = await engine.ingestText("第一段内容。", source: "s1.txt", title: "文档一")
        let hits = await engine.retrieve(query: "第一段内容")
        #expect(!hits.isEmpty)
        let c = hits[0].citation
        #expect(c.contains("文档一"))
        #expect(c.contains("s1.txt"))
        #expect(c.contains("块 1"))
        #expect(c.contains("字符 0-6"))
    }

    @Test func filterByMetadata() async {
        let engine = makeEngine()
        await engine.ingestText("swift 工具调用 超时 熔断", source: "a.md", metadata: ["tag": "backend"])
        await engine.ingestText("swift 工具调用 超时 熔断", source: "b.md", metadata: ["tag": "frontend"])
        let all = await engine.retrieve(query: "swift 工具 超时", options: .init(topK: 5))
        #expect(all.count == 2)
        let filtered = await engine.retrieve(query: "swift 工具 超时", options: .init(topK: 5, filter: ["tag": "frontend"]))
        #expect(filtered.count == 1)
        #expect(filtered[0].source == "b.md")
    }

    @Test func emptyQueryReturnsEmpty() async {
        let engine = makeEngine()
        await engine.ingestText("一些内容", source: "x")
        #expect(await (engine.retrieve(query: "   ")).isEmpty)
    }

    @Test func removeDocumentStopsHits() async {
        let engine = makeEngine()
        _ = await engine.ingestText("苹果 香蕉 橘子 水果篮子", source: "fruit.md")
        #expect(await !(engine.retrieve(query: "苹果 香蕉 橘子")).isEmpty)
        let ids = await engine.documentIDs()
        #expect(ids.count == 1)
        await engine.removeDocument(ids[0])
        #expect(await (engine.documentIDs()).isEmpty)
        #expect(await (engine.retrieve(query: "苹果 香蕉 橘子")).isEmpty)
    }

    @Test func documentIDsAndStats() async {
        let engine = makeEngine()
        _ = await engine.ingestText("甲内容甲内容甲内容", source: "d1.md")
        _ = await engine.ingestText("乙内容乙内容乙内容", source: "d2.md")
        let ids = await engine.documentIDs()
        #expect(ids.count == 2)
        let (docs, chunks, _) = await engine.stats()
        #expect(docs == 2)
        #expect(chunks >= 2)
    }

    @Test func ingestPathWithMetadataMerge() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rag-ingest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("notes.txt").path
        try "swift 沙箱 路径 校验 越界 拒绝".write(toFile: path, atomically: true, encoding: .utf8)
        let engine = makeEngine()
        let count = try await engine.ingestPath(path, metadata: ["tag": "sec"])
        #expect(count >= 1)
        let hits = await engine.retrieve(query: "swift 沙箱 越界", options: .init(filter: ["tag": "sec"]))
        #expect(!hits.isEmpty)
        #expect(hits[0].metadata["tag"] == "sec")
    }

    @Test func ingestPathNotFoundThrows() async {
        let engine = makeEngine()
        do {
            _ = try await engine.ingestPath("/nonexistent/nope.txt")
            Issue.record("应当抛出")
        } catch is DocumentLoadError {
            // 预期
        } catch {
            Issue.record("错误类型不对：\(error)")
        }
    }

    @Test func ingestEmptyTextZeroChunks() async {
        let engine = makeEngine()
        #expect(await engine.ingestText("   ", source: "empty.md") == 0)
        #expect(await engine.documentIDs().isEmpty)
    }

    @Test func reingestSameDocumentOverwrites() async {
        let engine = makeEngine()
        let doc = DocumentLoader.loadText("原始版本内容", source: "v.md", title: "V")
        _ = await engine.ingest(doc)
        let firstIDs = await engine.documentIDs()
        _ = await engine.ingest(doc) // 同 id 再入 → 覆盖不翻倍
        let secondIDs = await engine.documentIDs()
        #expect(firstIDs == secondIDs)
        #expect(await engine.count(documentID: firstIDs[0]) >= 1)
    }

    // MARK: - 去重（P2：同文件重复入库）

    @Test func ingestSameSourceTwiceDoesNotDuplicate() async {
        let engine = makeEngine()
        _ = await engine.ingestText("重复入库测试：swift 并发 actor 隔离", source: "f.md", title: "F")
        let (docs1, chunks1, _) = await engine.stats()
        _ = await engine.ingestText("重复入库测试：swift 并发 actor 隔离", source: "f.md", title: "F")
        let (docs2, chunks2, _) = await engine.stats()
        #expect(docs2 == 1)
        #expect(chunks2 == chunks1)
        let hits = await engine.retrieve(query: "重复入库 测试")
        #expect(hits.count == 1)
    }

    @Test func ingestSameSourceUpdatedContentReplaces() async {
        let engine = makeEngine()
        _ = await engine.ingestText("旧版本内容：苹果香蕉", source: "doc.md", title: "Doc")
        _ = await engine.ingestText("新版本内容：量子计算突破", source: "doc.md", title: "Doc")
        let (docs, _, _) = await engine.stats()
        #expect(docs == 1)
        // 旧内容不再命中，新内容命中
        #expect(await engine.retrieve(query: "苹果 香蕉").isEmpty)
        #expect(await !(engine.retrieve(query: "量子计算")).isEmpty)
    }

    @Test func differentSourceSameContentBothKept() async {
        let engine = makeEngine()
        _ = await engine.ingestText("相同正文两种来源", source: "a.md")
        _ = await engine.ingestText("相同正文两种来源", source: "b.md")
        let (docs, _, _) = await engine.stats()
        #expect(docs == 2)
    }

    @Test func ingestPathTwiceDedupes() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag-dedup-\(UUID().uuidString).txt")
        try "路径入库去重验证文本".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = makeEngine()
        _ = try await engine.ingestPath(url.path)
        _ = try await engine.ingestPath(url.path)
        let (docs, _, _) = await engine.stats()
        #expect(docs == 1)
    }

    @Test func saveRoundTripThroughFile() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rag-engine-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = RAGEngine(store: VectorStore(fileURL: url))
        _ = await engine.ingestText("持久化 验证 文本内容", source: "p.md")
        await engine.save()
        let reloaded = RAGEngine(store: VectorStore(fileURL: url))
        let (docs, _, _) = await reloaded.stats()
        #expect(docs == 1)
        #expect(await !(reloaded.retrieve(query: "持久化 验证")).isEmpty)
    }
}
