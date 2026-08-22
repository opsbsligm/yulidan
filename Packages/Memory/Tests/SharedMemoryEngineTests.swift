import Foundation
import Memory
import Testing

@Suite("SharedMemoryEngine 契约 v2 路径重路由", .serialized)
struct SharedMemoryEngineTests {
    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mem-shared-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func recordStrong(_ engine: MemoryEngine, content: String) async {
        _ = await engine.record(MemoryCandidate(
            content: content, kind: .fact, topic: "t-\(UUID().uuidString)",
            sourceSession: "test", origin: .manual, significanceFloor: 0.9
        ))
    }

    @Test("get 缓存：两次 get 同一实例（状态延续）")
    func getCachesEngine() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pathA = dir.appendingPathComponent("A/longterm.json")
        let shared = SharedMemoryEngine(fileURL: pathA)
        let e1 = await shared.get()
        await recordStrong(e1, content: "第一条记忆内容足够长")
        let e2 = await shared.get()
        let stats = await e2.stats()
        #expect(stats.active >= 1, "缓存实例应延续状态")
    }

    @Test("resetFileURL：丢弃旧实例，新 get 落新路径，旧数据不迁移")
    func resetFileURLReroutes() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pathA = dir.appendingPathComponent("A/longterm.json")
        let pathB = dir.appendingPathComponent("B/longterm.json")
        let shared = SharedMemoryEngine(fileURL: pathA)
        let ea = await shared.get()
        await recordStrong(ea, content: "A 根的记忆数据样本")
        await ea.save()
        #expect(FileManager.default.fileExists(atPath: pathA.path), "A 路径应落盘")

        await shared.resetFileURL(pathB)
        let eb = await shared.get()
        let statsB = await eb.stats()
        #expect(statsB.total == 0, "新路径应为空库（严格隔离不迁移）")
        await eb.save()
        #expect(FileManager.default.fileExists(atPath: pathB.path), "B 路径应落盘")
        // 再次 get 仍路由 B（缓存不回到 A）
        let eb2 = await shared.get()
        #expect(await (eb2.stats().total) == 0)
    }
}
