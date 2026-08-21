import Foundation
@testable import ServiceContainer
import Testing

private final class TestPlugin: Plugin, @unchecked Sendable {
    var manifest: PluginManifest
    var isActive: Bool = false
    var shouldFailInit = false
    var shouldFailStart = false
    var permissions: [Permission] = []

    init(id: String = "com.harness.test", name: String = "Test", permissions: [Permission] = []) {
        self.permissions = permissions
        manifest = PluginManifest(
            id: PluginID(id), name: name,
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "Test",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
            permissions: permissions
        )
    }

    func initialize(context _: PluginContext) async throws {
        if shouldFailInit {
            throw PluginInitError.failure
        }
    }

    func start(context _: PluginContext) async throws {
        isActive = true
        if shouldFailStart {
            throw PluginStartError.failure
        }
    }

    func stop(context _: PluginContext) async {
        isActive = false
    }
}

private enum PluginInitError: Error, Sendable { case failure }
private enum PluginStartError: Error, Sendable { case failure }

@Suite("PluginManager Tests")
struct PluginManagerTests {
    @Test("Install plugin")
    func testInstall() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        let plugin = TestPlugin()
        try await manager.install(plugin)
        #expect(await manager.isActive(plugin.manifest.id))
    }

    @Test("Duplicate install throws")
    func duplicate() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        let plugin = TestPlugin()
        try await manager.install(plugin)
        do {
            try await manager.install(plugin)
            Issue.record("Expected error")
        } catch {}
    }

    @Test("Uninstall plugin")
    func testUninstall() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        let plugin = TestPlugin()
        try await manager.install(plugin)
        try await manager.uninstall(plugin.manifest.id)
        #expect(await manager.isActive(plugin.manifest.id) == false)
    }

    @Test("Uninstall not found throws")
    func uninstallNotFound() async {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        do {
            try await manager.uninstall(PluginID("com.harness.none"))
            Issue.record("Expected error")
        } catch {}
    }

    @Test("List plugins")
    func testList() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        let plugin = TestPlugin()
        try await manager.install(plugin)
        let list = await manager.list()
        #expect(list.count == 1)
        #expect(list[0].id.rawValue == "com.harness.test")
    }

    @Test("Active plugins")
    func testActive() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        let plugin = TestPlugin()
        try await manager.install(plugin)
        let active = await manager.activePlugins()
        #expect(active.count == 1)
    }

    @Test("Stop all")
    func testStopAll() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        try await manager.install(TestPlugin(id: "com.harness.a", name: "A"))
        try await manager.install(TestPlugin(id: "com.harness.b", name: "B"))
        #expect(await manager.list().count == 2)
        await manager.stopAll()
        #expect(await manager.list().isEmpty)
    }

    @Test("Version mismatch throws")
    func versionMismatch() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus,
                                    harnessVersion: PluginVersion(major: 0, minor: 1, patch: 0))
        let plugin = TestPlugin()
        let manifest = PluginManifest(
            id: PluginID("com.harness.test"), name: "Test",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "Test",
            minHarnessVersion: PluginVersion(major: 99, minor: 0, patch: 0)
        )
        plugin.manifest = manifest
        do {
            try await manager.install(plugin)
            Issue.record("Expected error")
        } catch {}
    }

    @Test("Init failure throws")
    func initFailure() async throws {
        let container = ServiceContainer()
        let eventBus = EventBus()
        let manager = PluginManager(container: container, eventBus: eventBus)
        let plugin = TestPlugin()
        plugin.shouldFailInit = true
        do {
            try await manager.install(plugin)
            Issue.record("Expected error")
        } catch {}
    }

    // MARK: - P0.4 权限门禁

    @Test("权限门禁：高危未授予 → permissionDenied；授予后安装成功")
    func permissionGateRequiresGrant() async throws {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())
        let plugin = TestPlugin(id: "com.harness.test.gate", permissions: [.shellExecution, .filesystemWrite])
        do {
            try await manager.install(plugin)
            Issue.record("Expected permissionDenied")
        } catch let PluginError.permissionDenied(id, perms) {
            #expect(id == plugin.manifest.id)
            #expect(Set(perms) == Set([Permission.shellExecution, Permission.filesystemWrite]))
        }
        #expect(await manager.grantedPermissions(for: plugin.manifest.id).isEmpty)
        await manager.grantPermissions(plugin.manifest.id, plugin.manifest.permissions)
        #expect(await Set(manager.grantedPermissions(for: plugin.manifest.id)) == Set(plugin.manifest.permissions))
        try await manager.install(plugin)
        #expect(await manager.isActive(plugin.manifest.id))
    }

    @Test("权限门禁：仅 low 风险权限免授予直接安装")
    func permissionGateLowPasses() async throws {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())
        let plugin = TestPlugin(id: "com.harness.test.low", permissions: [.filesystemRead, .clipboardAccess])
        try await manager.install(plugin)
        #expect(await manager.isActive(plugin.manifest.id))
    }

    @Test("权限门禁：卸载撤销授予 → 重装需重新裁决")
    func permissionGateRevokeOnUninstall() async throws {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())
        let plugin = TestPlugin(id: "com.harness.test.revoke", permissions: [.terminalAccess])
        await manager.grantPermissions(plugin.manifest.id, plugin.manifest.permissions)
        try await manager.install(plugin)
        try await manager.uninstall(plugin.manifest.id)
        #expect(await manager.grantedPermissions(for: plugin.manifest.id).isEmpty)
        do {
            try await manager.install(plugin)
            Issue.record("Expected permissionDenied after revoke")
        } catch PluginError.permissionDenied(_, _) {
            // 预期路径
        }
    }

    @Test("PluginInfo 暴露 manifest 真实权限（UI 数据源）")
    func pluginInfoExposesPermissions() async throws {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())
        let plugin = TestPlugin(id: "com.harness.test.info", permissions: [.networkAccess, .keychainAccess])
        await manager.grantPermissions(plugin.manifest.id, plugin.manifest.permissions)
        try await manager.install(plugin)
        let infos = await manager.list()
        guard let info = infos.first(where: { $0.id == plugin.manifest.id }) else {
            Issue.record("plugin not listed")
            return
        }
        #expect(info.permissions == plugin.manifest.permissions)
    }
}
