import Foundation
@testable import HarnessApp
import ServiceContainer
import Testing

// MARK: - P0.4 权限门禁：安装裁决流（permissionDenied → 待裁决 → 授予并安装 / 拒绝）

/// 请求中/高危权限的测试插件
private final class HighPermTestPlugin: Plugin, @unchecked Sendable {
    var manifest: PluginManifest
    var isActive = false

    init() {
        manifest = PluginManifest(
            id: PluginID("com.harness.test.highperm"),
            name: "高危测试插件",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "Test",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
            permissions: [.shellExecution, .filesystemWrite]
        )
    }

    func initialize(context _: PluginContext) async throws {}
    func start(context _: PluginContext) async throws {
        isActive = true
    }

    func stop(context _: PluginContext) async {
        isActive = false
    }
}

@MainActor
@Suite("AppViewModel P0.4 权限门禁", .serialized)
struct AppViewModelPermissionGateTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func makeVM() -> AppViewModel {
        AppViewModel(
            skillUserDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-permgate-skills-\(UUID().uuidString)"),
            sessionDBURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-permgate-\(UUID().uuidString).sqlite")
        )
    }

    // MARK: 场景 1：安装触发 permissionDenied → 待裁决状态（含中文权限名）

    @Test("安装高危插件：permissionDenied → pendingPermissionInstall")
    func installSetsPending() async {
        let vm = makeVM()
        let plugin = HighPermTestPlugin()

        await vm.installPlugin(name: plugin.manifest.name, version: "1.0.0") {
            try await vm.pluginManager.install(plugin)
        }

        guard let pending = vm.pendingPermissionInstall else {
            Issue.record("期望 pendingPermissionInstall 非 nil")
            return
        }
        #expect(pending.id == "com.harness.test.highperm")
        #expect(pending.name == "高危测试插件")
        #expect(pending.permissions == ["Shell 执行", "文件写入"])
        // 插件未安装
        #expect(!vm.plugins.contains { $0.id == pending.id })
    }

    // MARK: 场景 2：裁决「授予并安装」→ 插件真实安装且 active

    @Test("授予并安装：插件进入 active 列表")
    func grantInstallsPlugin() async {
        let vm = makeVM()
        let plugin = HighPermTestPlugin()

        await vm.installPlugin(name: plugin.manifest.name, version: "1.0.0") {
            try await vm.pluginManager.install(plugin)
        }
        #expect(vm.pendingPermissionInstall != nil)

        await vm.grantPendingPermissionInstall()

        #expect(vm.pendingPermissionInstall == nil)
        guard let installed = vm.plugins.first(where: { $0.id == "com.harness.test.highperm" }) else {
            Issue.record("插件未出现在安装列表")
            return
        }
        #expect(installed.isActive)
        #expect(installed.permissions == ["Shell 执行", "文件写入"])
    }

    // MARK: 场景 3：裁决「拒绝」→ 插件保持未安装

    @Test("拒绝：插件保持未安装")
    func denyKeepsUninstalled() async {
        let vm = makeVM()
        let plugin = HighPermTestPlugin()

        await vm.installPlugin(name: plugin.manifest.name, version: "1.0.0") {
            try await vm.pluginManager.install(plugin)
        }
        #expect(vm.pendingPermissionInstall != nil)

        vm.denyPendingPermissionInstall()

        #expect(vm.pendingPermissionInstall == nil)
        #expect(!vm.plugins.contains { $0.id == "com.harness.test.highperm" })
    }
}
