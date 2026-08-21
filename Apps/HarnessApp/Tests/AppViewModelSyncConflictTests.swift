import Account
import Foundation
@testable import HarnessApp
import Testing
import Workspace

// MARK: - P0.1.4 iCloud 同步冲突裁决：回调挂起 / 保留本地 / 保留云端 / 纯函数

@MainActor
@Suite("AppViewModel P0.1.4 同步冲突裁决", .serialized)
struct AppViewModelSyncConflictTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func makeVM() -> AppViewModel {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-conflict-\(UUID().uuidString)")
        let vm = AppViewModel(
            skillUserDirectory: base.appendingPathComponent("skills"),
            sessionDBURL: base.appendingPathComponent("sessions.sqlite")
        )
        // 测试缩短安全网（用例内均主动裁决，fallback 仅兜底）
        vm.conflictAutoResolveDelay = .seconds(120)
        return vm
    }

    private func makeConflict(key: String = "harness.test.key") -> SyncConflict {
        let local = SyncedValue(value: Data("local-payload".utf8), updatedAt: .now, deviceId: "dev-A")
        let remote = SyncedValue(value: Data("remote-payload".utf8), updatedAt: .now, deviceId: "dev-B")
        return SyncConflict(key: key, local: local, remote: remote)
    }

    /// 等待 pending 列表出现（协作调度下不用固定 sleep 断言）
    private func waitPending(_ vm: AppViewModel, expectCount: Int = 1) async {
        for _ in 0 ..< 50 {
            if vm.pendingSyncConflicts.count == expectCount {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("裁决保留本地：回调挂起→UI 裁决→返回本地载荷 + 提示")
    func resolveKeepLocal() async {
        let vm = makeVM()
        let conflict = makeConflict()
        let task = Task { await vm.awaitUserResolution(conflict) }
        await waitPending(vm)
        #expect(vm.pendingSyncConflicts.count == 1)
        #expect(vm.pendingSyncConflicts.first?.key == conflict.key)
        #expect(vm.pendingSyncConflicts.first?.localPreview == "local-payload")
        #expect(vm.pendingSyncConflicts.first?.remotePreview == "remote-payload")
        #expect(vm.toastMessage?.contains("冲突") == true)

        defer { vm.resolveSyncConflict(id: vm.pendingSyncConflicts.first?.id ?? UUID(), keepLocal: true) }
        if let id = vm.pendingSyncConflicts.first?.id {
            vm.resolveSyncConflict(id: id, keepLocal: true)
        }
        let winner = await task.value
        #expect(winner == conflict.local)
        #expect(vm.pendingSyncConflicts.isEmpty)
        #expect(vm.toastMessage?.contains("保留本地") == true)
    }

    @Test("裁决保留云端：胜者 = 远端载荷")
    func resolveKeepRemote() async {
        let vm = makeVM()
        let conflict = makeConflict()
        let task = Task { await vm.awaitUserResolution(conflict) }
        await waitPending(vm)
        defer { vm.resolveSyncConflict(id: vm.pendingSyncConflicts.first?.id ?? UUID(), keepLocal: false) }
        if let id = vm.pendingSyncConflicts.first?.id {
            vm.resolveSyncConflict(id: id, keepLocal: false)
        }
        let winner = await task.value
        #expect(winner == conflict.remote)
        #expect(vm.pendingSyncConflicts.isEmpty)
        #expect(vm.toastMessage?.contains("保留云端") == true)
    }

    @Test("未知 id 裁决：no-op 不崩溃")
    func resolveUnknownIdNoOp() {
        let vm = makeVM()
        vm.resolveSyncConflict(id: UUID(), keepLocal: true)
        #expect(vm.pendingSyncConflicts.isEmpty)
    }

    @Test("syncKeyDisplay：已知键中文化 / 未知键透传")
    func keyDisplay() {
        #expect(AppViewModel.syncKeyDisplay(AccountService.keyAccountMode) == "账号模式")
        #expect(AppViewModel.syncKeyDisplay(WorkspaceSyncPayload.kvsKey) == "项目与会话数据")
        #expect(AppViewModel.syncKeyDisplay("custom.key") == "custom.key")
    }

    @Test("syncValuePreview：文本截断 / 二进制标注 / 空载荷")
    func valuePreview() {
        let long = SyncedValue(value: Data(String(repeating: "a", count: 200).utf8),
                               updatedAt: .now, deviceId: "d")
        let preview = AppViewModel.syncValuePreview(long)
        #expect(preview.count == 81, "80 字符 + 省略号，实际 \(preview.count)")
        #expect(preview.hasSuffix("…"))

        let binary = SyncedValue(value: Data([0x00, 0xFF, 0xFE]), updatedAt: .now, deviceId: "d")
        #expect(AppViewModel.syncValuePreview(binary) == "二进制数据（3 字节）")

        let empty = SyncedValue(value: Data(), updatedAt: .now, deviceId: "d")
        #expect(AppViewModel.syncValuePreview(empty).isEmpty)
    }
}
