@testable import Account
import Foundation
import Testing

/// 账号/工作区状态机全流程（fake 注入，纯逻辑）
@MainActor
struct AccountServiceTests {
    private func settle(_ ms: Int = 100) async throws {
        try await Task.sleep(for: .milliseconds(ms))
    }

    @Test func defaultStateIsLocal() throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        #expect(fx.service.state == .local)
        #expect(fx.service.lastError == nil)
    }

    @Test func signInSuccessWithAvailableICloudEntersReady() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()

        fx.service.signInWithApple()
        try await settle()

        #expect(fx.service.state == .icloudReady)
        #expect(fx.service.account?.userID == "user-test-001")
        #expect(fx.service.account?.email == "test@example.com")
        // 凭证已持久化
        #expect(try fx.credentialStore.load() != nil)
        // iCloud 工作区已物化标准目录
        let docs = fx.icloudContainer.appendingPathComponent("Documents", isDirectory: true)
        for dir in WorkspaceLayout.allDirectories {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: docs.appendingPathComponent(dir).path, isDirectory: &isDir)
            #expect(isDir.boolValue, "缺失 iCloud 子目录：\(dir)")
        }
        // 存储路由指向 iCloud
        #expect(fx.service.currentWorkspace.kind == .icloud)
    }

    @Test func signInSuccessButNoEntitlementDegrades() async throws {
        let fx = try AccountServiceFixture(icloudAvailable: false)
        defer { fx.cleanup() }
        fx.service.restore()

        fx.service.signInWithApple()
        try await settle()

        guard case let .icloudDegradedLocal(reason) = fx.service.state else {
            Issue.record("期望降级态，实际 \(fx.service.state)")
            return
        }
        #expect(reason.contains("entitlement"))
        #expect(fx.service.currentWorkspace.kind == .local)
        #expect(fx.service.lastError == reason)
    }

    @Test func signInSuccessButNoICloudAccountDegrades() async throws {
        let fx = try AccountServiceFixture(icloudAvailable: false, hasICloudAccount: false)
        defer { fx.cleanup() }
        fx.service.restore()

        fx.service.signInWithApple()
        try await settle()

        guard case let .icloudDegradedLocal(reason) = fx.service.state else {
            Issue.record("期望降级态，实际 \(fx.service.state)")
            return
        }
        #expect(reason.contains("iCloud 账号"))
    }

    @Test func signInUserCancelledReturnsToLocal() async throws {
        let signer = FakeAppleSigning(nextResult: .failure(AppleSignInError.userCancelled))
        let fx = try AccountServiceFixture(signer: signer)
        defer { fx.cleanup() }
        fx.service.restore()

        fx.service.signInWithApple()
        try await settle()

        #expect(fx.service.state == .local)
        #expect(fx.service.lastError == "已取消登录")
        #expect(signer.signInCalls == 1)
        #expect(try fx.credentialStore.load() == nil)
    }

    @Test func doubleSignInWhilePendingIsIgnored() async throws {
        let signer = FakeAppleSigning()
        signer.deliverMode = .delayed
        let fx = try AccountServiceFixture(signer: signer)
        defer { fx.cleanup() }
        fx.service.restore()

        fx.service.signInWithApple()
        #expect(fx.service.state == .ssoPending)
        fx.service.signInWithApple() // 第二次应被忽略
        #expect(signer.signInCalls == 1)

        // 有界等待 delayed 投递（30ms）+ 激活链完成（固定 200ms 可被负载下调度滞后突破；P1 flake 修复）
        for _ in 0 ..< 150 {
            if fx.service.state == .icloudReady {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fx.service.state == .icloudReady)
        #expect(signer.signInCalls == 1)
    }

    @Test func restorePersistedICloudModeRecoversReady() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state == .icloudReady)

        // 模拟 App 重启：新服务实例 + 相同 settings/凭证库
        let service2 = fx.makeService()
        service2.restore()
        try await settle()
        #expect(service2.state == .icloudReady)
        #expect(service2.account?.userID == "user-test-001")
    }

    @Test func restoreWithRevokedCredentialDegradesAndForgets() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state == .icloudReady)

        // 用户撤销授权后重启
        fx.signer.nextCredentialState = .revoked
        let service2 = fx.makeService()
        service2.restore()
        try await settle()

        #expect(service2.state.degradationReason?.contains("撤销") == true)
        #expect(try fx.credentialStore.load() == nil)
    }

    @Test func restoreWithoutCredentialDegrades() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state == .icloudReady)

        // 凭证库被清空后重启（如钥匙串被重置）
        let emptyStore = InMemoryCredentialStore()
        let service2 = fx.makeService(credentialStore: emptyStore)
        service2.restore()
        try await settle()

        #expect(service2.state.degradationReason != nil)
        #expect(service2.state.mode == .local)
    }

    @Test func switchToLocalModeFromReady() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state == .icloudReady)

        fx.service.switchToLocalMode()
        #expect(fx.service.state == .local)
        #expect(fx.service.currentWorkspace.kind == .local)
        // 凭证保留（仅切存储模式，不清账号）
        #expect(try fx.credentialStore.load() != nil)
    }

    @Test func retryICloudRecoversAfterEntitlementGranted() async throws {
        let fx = try AccountServiceFixture(icloudAvailable: false)
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state.degradationReason != nil)

        // "描述文件配置完成"：容器可用
        fx.probe.containerURL = fx.icloudContainer
        fx.service.retryICloud()

        #expect(fx.service.state == .icloudReady)
        #expect(fx.service.lastError == nil)
    }

    @Test func retryICloudWithoutAccountShowsError() throws {
        let fx = try AccountServiceFixture(icloudAvailable: false)
        defer { fx.cleanup() }
        fx.service.restore()

        fx.service.retryICloud()
        #expect(fx.service.lastError == "请先使用 Apple ID 登录")
        #expect(fx.service.state == .local)
    }

    @Test func retryICloudStillUnavailableStaysDegraded() async throws {
        let fx = try AccountServiceFixture(icloudAvailable: false)
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state.degradationReason != nil)

        fx.service.retryICloud()
        #expect(fx.service.state.degradationReason?.contains("entitlement") == true)
    }

    @Test func signOutClearsCredentialAndReturnsToLocal() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state == .icloudReady)

        fx.service.signOut()
        #expect(fx.service.state == .local)
        #expect(fx.service.account == nil)
        #expect(try fx.credentialStore.load() == nil)
    }

    @Test func reSignInAfterLocalModePassesExistingUserID() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.service.state == .icloudReady)

        fx.service.switchToLocalMode()
        #expect(fx.signer.signInCalls == 1)
        fx.service.signInWithApple()
        try await settle()
        #expect(fx.signer.signInCalls == 2)
        #expect(fx.signer.lastExistingUserID == "user-test-001")
    }

    @Test func kvsAccountChangeDegradesToICloud() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle(200)
        #expect(fx.service.state == .icloudReady)

        let accountChanged = await fx.service.handleKVSExternalChange(reason: .accountChange)
        #expect(accountChanged)
        #expect(fx.service.state.degradationReason?.contains("账号") == true)
        #expect(fx.service.state.mode == .local)
    }

    @Test func kvsServerChangeDoesNotDegrade() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await settle(200)
        #expect(fx.service.state == .icloudReady)

        let accountChanged = await fx.service.handleKVSExternalChange(reason: .serverChange)
        #expect(!accountChanged)
        #expect(fx.service.state == .icloudReady)
    }
}

// MARK: - P0.1.4 冲突裁决 handler 转发链（setConflictHandler → sync → 冲突 → 裁决 → 胜者落 KVS）

final class ConflictBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: SyncConflict?

    var value: SyncConflict? {
        lock.withLock { _value }
    }

    func set(_ v: SyncConflict) {
        lock.withLock { _value = v }
    }
}

@MainActor
@Suite("AccountService P0.1.4 冲突裁决转发")
struct AccountServiceConflictTests {
    private func settle(_ ms: Int = 200) async throws {
        try await Task.sleep(for: .milliseconds(ms))
    }

    private static func encode(_ v: SyncedValue) -> Data {
        (try? JSONEncoder().encode(v)) ?? Data()
    }

    private static func decode(_ d: Data?) -> SyncedValue? {
        d.flatMap { try? JSONDecoder().decode(SyncedValue.self, from: $0) }
    }

    @Test("handler 转发生效：冲突触发 UI 裁决，胜者写回 KVS")
    func conflictHandlerForwardsAndWinnerApplied() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        let kvs = FakeKVS()
        let service = AccountService(
            rootProvider: WorkspaceRootProvider(
                localRoot: fx.tempDir.appendingPathComponent("LocalRootConflict", isDirectory: true),
                probe: fx.probe
            ),
            probe: fx.probe,
            credentialStore: fx.credentialStore,
            signingFactory: { fx.signer },
            settingsURL: fx.tempDir.appendingPathComponent("account-conflict.json"),
            kvsStoreFactory: { kvs }
        )
        service.restore()
        service.signInWithApple()
        try await settle(300)
        #expect(service.state == .icloudReady)
        // 有界等待激活期 fire-and-forget KVS publish（"ssoIcloud"）落盘：
        // 迟落会覆盖后续冲突裁决终值（P1 flake 根因：9 字节 "ssoIcloud" 覆盖裁决值）
        for _ in 0 ..< 150 {
            if kvs.data(forKey: AccountService.keyAccountMode) != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kvs.data(forKey: AccountService.keyAccountMode) != nil, "激活 publish 应落 KVS")

        let box = ConflictBox()
        // 用户裁决：保留云端
        service.setConflictHandler { conflict in
            box.set(conflict)
            return conflict.remote
        }
        try await settle()

        // 预埋异设备云端值（另一台设备已写入）
        let foreign = SyncedValue(value: Data("remote-v".utf8), updatedAt: .now, deviceId: "dev-B")
        kvs.set(Self.encode(foreign), forKey: AccountService.keyAccountMode)
        // 本机新写入 → push 遇异设备值 → 冲突 → 裁决 handler
        await service.testPublish(key: AccountService.keyAccountMode, value: Data("local-v2".utf8))
        try await settle()

        #expect(box.value != nil, "冲突回调应被触发")
        #expect(box.value?.local.value == Data("local-v2".utf8))
        #expect(box.value?.remote.value == Data("remote-v".utf8))
        #expect(box.value?.key == AccountService.keyAccountMode)
        // 裁决保留云端 → KVS 终值 = 云端载荷
        #expect(Self.decode(kvs.data(forKey: AccountService.keyAccountMode))?.value == Data("remote-v".utf8))
    }

    @Test("handler 在 signIn 前设置：激活时同样下发生效")
    func handlerSetBeforeSignIn() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        let kvs = FakeKVS()
        let service = AccountService(
            rootProvider: WorkspaceRootProvider(
                localRoot: fx.tempDir.appendingPathComponent("LocalRootConflict2", isDirectory: true),
                probe: fx.probe
            ),
            probe: fx.probe,
            credentialStore: fx.credentialStore,
            signingFactory: { fx.signer },
            settingsURL: fx.tempDir.appendingPathComponent("account-conflict2.json"),
            kvsStoreFactory: { kvs }
        )
        // 先设置 handler（未激活），再登录
        let box = ConflictBox()
        service.setConflictHandler { conflict in
            box.set(conflict)
            return conflict.local
        }
        service.restore()
        service.signInWithApple()
        try await settle(300)
        #expect(service.state == .icloudReady)
        // 有界等待激活期 fire-and-forget KVS publish（"ssoIcloud"）落盘：
        // 迟落会覆盖后续冲突裁决终值（P1 flake 根因：9 字节 "ssoIcloud" 覆盖裁决值）
        for _ in 0 ..< 150 {
            if kvs.data(forKey: AccountService.keyAccountMode) != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kvs.data(forKey: AccountService.keyAccountMode) != nil, "激活 publish 应落 KVS")

        let foreign = SyncedValue(value: Data("remote-x".utf8), updatedAt: .now, deviceId: "dev-B")
        kvs.set(Self.encode(foreign), forKey: AccountService.keyAccountMode)
        await service.testPublish(key: AccountService.keyAccountMode, value: Data("local-y".utf8))
        try await settle()

        #expect(box.value != nil)
        #expect(Self.decode(kvs.data(forKey: AccountService.keyAccountMode))?.value == Data("local-y".utf8), "裁决保留本地")
    }
}
