import Foundation
import RAG
import Testing

// MARK: - SharedRAGEngine 索引重路由（P0.1.5 双根严格隔离：本地 ⇄ iCloud 不迁移数据）

@Suite("SharedRAGEngine 索引重路由")
struct SharedRAGEngineRoutingTests {
    @Test("resetIndexURL 后新引擎读新路径：旧根数据不泄漏；旧文件保留（严格隔离不迁移）")
    func resetIsolatesStores() async {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rag-routing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let a = base.appendingPathComponent("A/rag/index.json")
        let b = base.appendingPathComponent("B/rag/index.json")

        let shared = SharedRAGEngine(indexURL: a)
        let ragA = await shared.get()
        _ = await ragA.ingestText("hello from root A", source: "docA")
        await ragA.save()
        #expect(await !(ragA.retrieve(query: "hello")).isEmpty)

        // 切根：新引擎在新路径上重建
        await shared.resetIndexURL(b)
        let ragB = await shared.get()
        // 旧根数据不得泄漏进新根（严格隔离）
        #expect(await (ragB.retrieve(query: "hello")).isEmpty)
        _ = await ragB.ingestText("hello from root B", source: "docB")
        await ragB.save()
        #expect(await !(ragB.retrieve(query: "hello")).isEmpty)

        // 双根各自落盘（无迁移、无清除）
        #expect(FileManager.default.fileExists(atPath: a.path), "旧根索引文件应保留")
        #expect(FileManager.default.fileExists(atPath: b.path), "新根索引应落盘")
    }

    @Test("resetIndexURL 幂等：重复 reset 同一路径重建引擎，既有数据保留")
    func resetIdempotent() async {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rag-routing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let a = base.appendingPathComponent("A/rag/index.json")
        let shared = SharedRAGEngine(indexURL: a)
        let ragA = await shared.get()
        _ = await ragA.ingestText("persistent document", source: "docP")
        await ragA.save()

        await shared.resetIndexURL(a)
        let ragA2 = await shared.get()
        #expect(await !(ragA2.retrieve(query: "persistent")).isEmpty, "同路径 reset 后既有数据应保留")
        await shared.resetIndexURL(a)
        #expect(await !(shared.get().retrieve(query: "persistent")).isEmpty)
    }
}
