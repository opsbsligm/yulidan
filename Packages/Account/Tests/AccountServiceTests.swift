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

        try await settle(200)
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
