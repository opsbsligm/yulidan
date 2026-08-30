import Foundation
@testable import HarnessApp
import Memory
import Testing

// MARK: - 契约 v2：长期记忆随工作区根路由（2026-08-30 起纯本地单根 + 旧路径一次性迁移）

// 从 WorkspaceRoutingTests 拆出（SwiftLint file_length ≤ 600）；夹具复用 AppWorkspaceFixture

private func settle(_ ms: Int = 200) async throws {
    try await Task.sleep(for: .milliseconds(ms))
}

@MainActor
@Suite("AppViewModel 契约 v2 记忆路由", .serialized)
struct AppViewModelMemoryRoutingTests {
    // MARK: - 契约 v2：长期记忆路由本地根 + 落盘可读

    @Test("契约 v2：记忆重路由落本地根 + 落盘后新引擎可读（单根闭环）")
    func localRootReroutesMemory() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        try await settle(400) // init Task 链：记忆重路由到当前根须先于首次 get()

        #expect(vm.workspaceRouter.memoryStoreURL
            == fx.localRoot.appendingPathComponent("memory/longterm.json"))

        // 本地根写入记忆并落盘
        let mem = await vm.sharedMemory.get()
        _ = await mem.record(MemoryCandidate(
            content: "本地根记忆数据样本，内容足够长", kind: .fact, topic: "mem-root-test",
            sourceSession: "t1", origin: .manual, significanceFloor: 0.9
        ))
        await mem.save()
        #expect(FileManager.default.fileExists(
            atPath: fx.localRoot.appendingPathComponent("memory/longterm.json").path
        ),
        "本地根记忆应落盘")

        // 路由指向的正是落盘文件；同根引擎读取可见（无跨根隔离问题——单根）
        let reread = await vm.sharedMemory.get()
        #expect(await (reread.stats()).total >= 1, "本地根记忆应可读")
        let recalled = await reread.recall(query: "记忆数据样本")
        #expect(recalled.contains { $0.topic == "mem-root-test" })
    }

    @Test("契约 v2 迁移：旧固定路径 → 本地根 memory/（一次性幂等）")
    func migrateLegacyMemoryScenarios() throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        let legacy = fx.tempDir.appendingPathComponent("legacy/longterm.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = #"{\"items\":{\"k1\":{\"topic\":\"t\"}},\"version\":1,\"revision\":3}"#
        try payload.write(to: legacy, atomically: true, encoding: .utf8)

        // ① 本地根 + 目标缺失 → 迁移成功（内容一致，旧文件保留不删）
        let target = fx.localRoot.appendingPathComponent("memory/longterm.json")
        #expect(vm.migrateLegacyMemoryIfNeeded(legacyURL: legacy) == true, "应发生一次性迁移")
        #expect(try String(contentsOf: target, encoding: .utf8) == payload, "迁移内容应一致")
        #expect(FileManager.default.fileExists(atPath: legacy.path), "旧文件应保留")
        // ② 幂等：目标已存在 → 不再迁移
        #expect(vm.migrateLegacyMemoryIfNeeded(legacyURL: legacy) == false, "目标已存在不得覆盖迁移")
        // ③ 旧文件缺失 → 不迁移
        #expect(vm.migrateLegacyMemoryIfNeeded(legacyURL: legacy.deletingLastPathComponent()
                .appendingPathComponent("none.json")) == false)
    }
}
