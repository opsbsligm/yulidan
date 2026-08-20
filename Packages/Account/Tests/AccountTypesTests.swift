@testable import Account
import Foundation
import ServiceContainer
import Testing

/// 类型层纯逻辑：探测判定 / 状态机语义 / 变更原因映射
struct AccountTypesTests {
    @Test func probeDecisionMatrix() {
        let container = URL(fileURLWithPath: "/tmp/probe-test")
        #expect(ICloudProbe(containerURL: container, hasICloudAccount: true).result == .available)
        #expect(ICloudProbe(containerURL: container, hasICloudAccount: false).result == .available)
        #expect(ICloudProbe(containerURL: nil, hasICloudAccount: false).result == .noICloudAccount)
        #expect(ICloudProbe(containerURL: nil, hasICloudAccount: true).result == .noEntitlement)
    }

    @Test func probeAvailability() {
        #expect(ICloudProbe(containerURL: URL(fileURLWithPath: "/tmp/x"), hasICloudAccount: true).isAvailable)
        #expect(!ICloudProbe(containerURL: nil, hasICloudAccount: true).isAvailable)
    }

    @Test func stateModeMapping() {
        #expect(WorkspaceState.local.mode == .local)
        #expect(WorkspaceState.icloudReady.mode == .ssoIcloud)
        #expect(WorkspaceState.ssoPending.mode == .local)
        #expect(WorkspaceState.icloudDegradedLocal(reason: "r").mode == .local)
    }

    @Test func stateICloudReadyFlag() {
        #expect(WorkspaceState.icloudReady.isICloudReady)
        #expect(!WorkspaceState.local.isICloudReady)
        #expect(!WorkspaceState.ssoPending.isICloudReady)
        #expect(!WorkspaceState.icloudDegradedLocal(reason: "r").isICloudReady)
    }

    @Test func degradationReasonOnlyInDegradedState() {
        #expect(WorkspaceState.icloudDegradedLocal(reason: "no account").degradationReason == "no account")
        #expect(WorkspaceState.local.degradationReason == nil)
        #expect(WorkspaceState.icloudReady.degradationReason == nil)
        #expect(WorkspaceState.ssoPending.degradationReason == nil)
    }

    @Test func kvsChangeReasonMapping() {
        #expect(AccountService.mapChangeReason(0) == .serverChange)
        #expect(AccountService.mapChangeReason(1) == .initialSyncChange)
        #expect(AccountService.mapChangeReason(2) == .quotaViolationChange)
        #expect(AccountService.mapChangeReason(3) == .accountChange)
        #expect(AccountService.mapChangeReason(99) == .unknown)
        #expect(AccountService.mapChangeReason(nil) == .unknown)
    }

    @Test func probeDescriptionTexts() {
        let container = URL(fileURLWithPath: "/tmp/x")
        #expect(AccountService.describe(ICloudProbe(containerURL: container, hasICloudAccount: true)).contains("可用"))
        #expect(AccountService.describe(ICloudProbe(containerURL: nil, hasICloudAccount: false)).contains("iCloud 账号"))
        #expect(AccountService.describe(ICloudProbe(containerURL: nil, hasICloudAccount: true)).contains("entitlement"))
    }
}

/// 默认实现真实环境安全运行（无 entitlement 开发/CI 环境：容器不可用；描述文件就绪后可用）
struct DefaultProbeTests {
    @Test func defaultProbeRunsSafely() {
        let probe = DefaultUbiquityProbe()
        let p = probe.probe(containerIdentifier: "iCloud.com.deepseek.harness")
        if p.containerURL == nil {
            #expect(p.result == .noICloudAccount || p.result == .noEntitlement)
        } else {
            #expect(p.result == .available)
        }
    }
}

/// Provider DI 注册往返
struct AccountServiceProviderTests {
    @Test func providerRegistersAccountService() async {
        let container = ServiceContainer()
        do {
            try await AccountServiceProvider().provide(to: container)
        } catch {
            Issue.record("provide 失败：\(error)")
        }
        let service: AccountService? = await container.tryResolve(AccountService.self)
        #expect(service != nil)
    }
}
