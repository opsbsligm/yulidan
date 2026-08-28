import Account
@testable import HarnessApp
import Testing

// MARK: - 侧栏 iCloud 同步状态提示（P2.2.2）：纯逻辑映射 + 展示文案不变量

@Suite("SidebarSyncHint 状态映射")
struct SidebarSyncHintTests {
    @Test("本地模式 = hidden（用户主动选择，不显示提示避免噪声）")
    func localHidden() {
        #expect(SidebarSyncHint.resolve(state: .local, isOnline: nil) == .hidden)
        #expect(SidebarSyncHint.resolve(state: .local, isOnline: true) == .hidden)
    }

    @Test("SSO 流程中 = connecting")
    func ssoPendingConnecting() {
        #expect(SidebarSyncHint.resolve(state: .ssoPending, isOnline: nil) == .connecting)
    }

    @Test("icloudReady：首探未返回(nil) = connecting；true = online；false = offline")
    func icloudReadyMatrix() {
        #expect(SidebarSyncHint.resolve(state: .icloudReady, isOnline: nil) == .connecting)
        #expect(SidebarSyncHint.resolve(state: .icloudReady, isOnline: true) == .online)
        #expect(SidebarSyncHint.resolve(state: .icloudReady, isOnline: false) == .offline)
    }

    @Test("降级态 = degraded 且保留原因")
    func degradedKeepsReason() {
        let hint = SidebarSyncHint.resolve(state: .icloudDegradedLocal(reason: "权限被拒"), isOnline: nil)
        #expect(hint == .degraded(reason: "权限被拒"))
    }

    @Test("hidden 无展示文案；其余态 icon/label/help 非空")
    func presentationInvariants() {
        #expect(SidebarSyncHint.hidden.icon.isEmpty)
        #expect(SidebarSyncHint.hidden.label.isEmpty)
        for hint in [
            SidebarSyncHint.connecting, .online, .offline, .degraded(reason: "x"),
        ] {
            #expect(!hint.icon.isEmpty, "icon 缺失")
            #expect(!hint.label.isEmpty, "label 缺失")
            #expect(!hint.help.isEmpty, "help 缺失")
        }
    }

    @Test("degraded 的 help 携带降级原因（处置引导）")
    func degradedHelpContainsReason() {
        let hint = SidebarSyncHint.degraded(reason: "iCloud 账号已变更")
        #expect(hint.help.contains("iCloud 账号已变更"))
    }

    @Test("online/offline 态 help 均引导至「账号与同步」")
    func helpGuidesToAccountPage() {
        #expect(SidebarSyncHint.online.help.contains("账号与同步"))
        #expect(SidebarSyncHint.offline.help.contains("账号与同步"))
        #expect(SidebarSyncHint.degraded(reason: "x").help.contains("账号与同步"))
    }
}
