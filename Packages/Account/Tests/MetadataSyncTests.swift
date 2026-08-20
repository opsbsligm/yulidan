@testable import Account
import Foundation
import Testing

/// KVS 元数据同步：离线优先 / 冲突裁决 / 账号变更 / 队列持久化
struct MetadataSyncTests {
    private func makeStagingDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kvs-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func encode(_ v: SyncedValue) -> Data {
        (try? JSONEncoder().encode(v)) ?? Data()
    }

    private static func decode(_ data: Data?) -> SyncedValue? {
        data.flatMap { try? JSONDecoder().decode(SyncedValue.self, from: $0) }
    }

    @Test func publishToEmptyRemoteWritesAndClearsPending() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        let sync = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")

        await sync.publish(key: "k1", value: Data("v1".utf8))

        #expect(await sync.pendingKeys.isEmpty)
        let raw = kvs.data(forKey: "k1")
        #expect(Self.decode(raw)?.value == Data("v1".utf8))
        #expect(Self.decode(raw)?.deviceId == "dev-A")
        #expect(await sync.value(forKey: "k1") == Data("v1".utf8))
    }

    @Test func publishWithForeignRemoteKeepsLocalWithoutCallback() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        // 预埋异设备值
        let foreign = SyncedValue(value: Data("remote".utf8), updatedAt: .now, deviceId: "dev-B")
        kvs.set(Self.encode(foreign), forKey: "k1")

        let sync = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        await sync.publish(key: "k1", value: Data("local".utf8))

        // 无回调 → 保留本地：pending 未清空，生效值为本地
        #expect(await sync.pendingKeys == ["k1"])
        #expect(await sync.value(forKey: "k1") == Data("local".utf8))
    }

    @Test func conflictCallbackWinnerIsWrittenToStore() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        let foreign = SyncedValue(value: Data("remote".utf8), updatedAt: .now, deviceId: "dev-B")
        kvs.set(Self.encode(foreign), forKey: "k1")

        let sync = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        // 用户裁决：保留远端
        await sync.setOnConflict { conflict in
            conflict.remote
        }
        await sync.publish(key: "k1", value: Data("local".utf8))

        #expect(await sync.pendingKeys.isEmpty)
        #expect(Self.decode(kvs.data(forKey: "k1"))?.value == Data("remote".utf8))
        #expect(await sync.value(forKey: "k1") == Data("remote".utf8))
    }

    @Test func sameDeviceIdenticalValueNoConflict() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        let existing = SyncedValue(value: Data("v1".utf8), updatedAt: .now, deviceId: "dev-A")
        kvs.set(Self.encode(existing), forKey: "k1")

        let sync = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        let conflicts = ConflictCounter()
        await sync.setOnConflict { _ in
            conflicts.bump()
            return SyncedValue(value: Data("x".utf8), updatedAt: .now, deviceId: "dev-A")
        }
        await sync.publish(key: "k1", value: Data("v1".utf8))

        #expect(await sync.pendingKeys.isEmpty)
        #expect(conflicts.isEmpty)
    }

    @Test func accountChangeClearsStateAndSignalsCaller() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        let foreign = SyncedValue(value: Data("remote".utf8), updatedAt: .now, deviceId: "dev-B")
        kvs.set(Self.encode(foreign), forKey: "k1")

        let sync = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        await sync.publish(key: "k1", value: Data("local".utf8))
        #expect(await sync.pendingKeys == ["k1"])

        let accountChanged = await sync.handleExternalChange(reason: .accountChange)
        #expect(accountChanged)
        #expect(await sync.pendingKeys.isEmpty)
    }

    @Test func serverChangeTriggersPullNotAccountSwitch() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        let sync = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        await sync.configure(managedKeys: ["k1"])
        let changed = await sync.handleExternalChange(reason: .serverChange)
        #expect(!changed)
    }

    @Test func stagingQueueSurvivesRestart() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        let foreign = SyncedValue(value: Data("remote".utf8), updatedAt: .now, deviceId: "dev-B")
        kvs.set(Self.encode(foreign), forKey: "k1")

        // 第一实例：冲突且无回调 → pending 留队
        let sync1 = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        await sync1.publish(key: "k1", value: Data("local".utf8))
        #expect(await sync1.pendingKeys == ["k1"])

        // 第二实例：从磁盘恢复队列
        let sync2 = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        await sync2.loadStaging()
        #expect(await sync2.pendingKeys == ["k1"])
        #expect(await sync2.value(forKey: "k1") == Data("local".utf8))
    }

    @Test func isOnlineReflectsStoreSynchronize() async throws {
        let kvs = FakeKVS()
        let staging = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: staging) }
        let sync = MetadataSyncService(store: kvs, stagingDir: staging, deviceId: "dev-A")
        #expect(await sync.isOnline())
        kvs.setSuccess(false)
        #expect(await !(sync.isOnline()))
        #expect(kvs.syncCalls >= 2)
    }
}
