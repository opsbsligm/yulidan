import Account
import Foundation
@testable import HarnessApp
import Memory
import Testing

// MARK: - 契约 v2：长期记忆随工作区根漫游（双根严格隔离 + 旧路径一次性迁移）

// 从 WorkspaceRoutingTests 拆出（SwiftLint file_length ≤ 600）；夹具复用 AppWorkspaceFixture

private func settle(_ ms: Int = 200) async throws {
    try await Task.sleep(for: .milliseconds(ms))
}

@MainActor
@Suite("AppViewModel 契约 v2 记忆路由", .serialized)
struct AppViewModelMemoryRoutingTests {
    // MARK: - 契约 v2：长期记忆随工作区根漫游（双根严格隔离 + 旧路径一次性迁移）

    @Test("契约 v2：切 iCloud 长期记忆重路由入容器 + 旧数据不迁移（严格隔离）")
    func switchToICloudReroutesMemory() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        try await settle(400) // init Task 链：记忆重路由到当前根须先于首次 get()

        // 本地根写入记忆并落盘
        let localMem = await vm.sharedMemory.get()
        _ = await localMem.record(MemoryCandidate(
            content: "本地根记忆数据样本，内容足够长", kind: .fact, topic: "mem-root-test",
            sourceSession: "t1", origin: .manual, significanceFloor: 0.9
        ))
        await localMem.save()
        #expect(FileManager.default.fileExists(
            atPath: fx.localRoot.appendingPathComponent("memory/longterm.json").path
        ),
        "本地根记忆应落盘")

        try await fx.signInToICloud()
        #expect(fx.service.state == .icloudReady)
        try await settle(400) // accountObservation sink Task（refresh + handleWorkspaceRootChanged）

        // 记忆已重路由：路由指向容器，新引擎为空库（本地根旧数据不迁移）
        let docs = fx.icloudContainer.appendingPathComponent("Documents", isDirectory: true)
        #expect(vm.workspaceRouter.memoryStoreURL == docs.appendingPathComponent("memory/longterm.json"))
        let newMem = await vm.sharedMemory.get()
        #expect(await (newMem.stats()).total == 0, "新根记忆应为空库（严格隔离）")
        // 向新根写入 → 容器 memory/longterm.json 落盘；本地根旧数据不得泄漏
        _ = await newMem.record(MemoryCandidate(
            content: "iCloud 根记忆数据样本，内容足够长", kind: .fact, topic: "mem-cloud-test",
            sourceSession: "t2", origin: .manual, significanceFloor: 0.9
        ))
        await newMem.save()
        #expect(FileManager.default.fileExists(atPath: docs.appendingPathComponent("memory/longterm.json").path))
        let recalled = await newMem.recall(query: "记忆数据样本")
        #expect(recalled.allSatisfy { $0.topic != "mem-root-test" }, "本地根记忆不得泄漏进 iCloud 根")
    }

    @Test("契约 v2 迁移：旧固定路径 → 本地根 memory/（一次性幂等；iCloud 模式不迁移）")
    func migrateLegacyMemoryScenarios() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        let legacy = fx.tempDir.appendingPathComponent("legacy/longterm.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = #"{\"items\":{\"k1\":{\"topic\":\"t\"}},\"version\":1,\"revision\":3}"#
        try payload.write(to: legacy, atomically: true, encoding: .utf8)

        // ① 本地模式 + 目标缺失 → 迁移成功（内容一致，旧文件保留不删）
        let target = fx.localRoot.appendingPathComponent("memory/longterm.json")
        #expect(vm.migrateLegacyMemoryIfNeeded(legacyURL: legacy) == true, "应发生一次性迁移")
        #expect(try String(contentsOf: target, encoding: .utf8) == payload, "迁移内容应一致")
        #expect(FileManager.default.fileExists(atPath: legacy.path), "旧文件应保留")
        // ② 幂等：目标已存在 → 不再迁移
        #expect(vm.migrateLegacyMemoryIfNeeded(legacyURL: legacy) == false, "目标已存在不得覆盖迁移")
        // ③ 旧文件缺失 → 不迁移
        #expect(vm.migrateLegacyMemoryIfNeeded(legacyURL: legacy.deletingLastPathComponent()
                .appendingPathComponent("none.json")) == false)

        // ④ iCloud 模式：不迁移（双根严格隔离，容器从空开始）
        try await fx.signInToICloud()
        #expect(fx.service.state == .icloudReady)
        try await settle(400)
        #expect(FileManager.default.fileExists(
            atPath: fx.icloudContainer.appendingPathComponent("Documents/memory/longterm.json").path
        ) == false,
        "iCloud 模式不得迁移旧数据入容器")
    }
}
