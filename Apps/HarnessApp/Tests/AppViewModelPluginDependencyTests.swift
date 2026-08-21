import Foundation
@testable import HarnessApp
import ServiceContainer
import Testing

// MARK: - P0.4⑤ 依赖缺失 UI：市场条目依赖满足度随依赖插件安装/卸载实时变化

private final class DependencyStubPlugin: Plugin, @unchecked Sendable {
    var manifest: PluginManifest
    var isActive: Bool = false

    init(id: String = "com.harness.depstub", name: String = "依赖桩", version: (Int, Int, Int) = (1, 0, 0)) {
        manifest = PluginManifest(
            id: PluginID(id), name: name,
            version: PluginVersion(major: version.0, minor: version.1, patch: version.2),
            description: "Test",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
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
@Suite("AppViewModel P0.4 依赖缺失 UI", .serialized)
struct AppViewModelPluginDependencyTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func makeVM() -> AppViewModel {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-dep-\(UUID().uuidString)")
        return AppViewModel(
            skillUserDirectory: base.appendingPathComponent("skills"),
            sessionDBURL: base.appendingPathComponent("sessions.sqlite")
        )
    }

    @Test("市场条目：依赖满足（终端已装）→ dependencies 展示名 + missing 空")
    func dependencySatisfiedShown() async {
        let vm = makeVM()
        await vm.loadPluginsInfrastructure()

        guard let item = vm.marketplaceEntries.first(where: { $0.name == "终端增强（依赖演示）" }) else {
            Issue.record("市场缺少 terminal-plus 演示条目")
            return
        }
        #expect(item.dependencies == ["终端"], "依赖标签应解析为展示名：\(item.dependencies)")
        #expect(item.missingDependencies.isEmpty)
    }

    @Test("卸载依赖插件 → 市场条目 missingDependencies 实时标记 + 依赖标签回落 id")
    func missingDependencyAfterUninstall() async throws {
        let vm = makeVM()
        await vm.loadPluginsInfrastructure()

        try await vm.pluginManager.uninstall(PluginID("terminal"))
        await vm.refreshMarketplace()

        guard let item = vm.marketplaceEntries.first(where: { $0.id == "terminal-plus" }) else {
            Issue.record("市场缺少 terminal-plus 条目")
            return
        }
        // 未安装 → 标签回落 id 原文；required 且未安装 → missing 非空
        #expect(item.dependencies == ["terminal"])
        #expect(item.missingDependencies == ["terminal"])

        // 安装被依赖插件后恢复满足（展示名重新解析）
        try await vm.pluginManager.install(DependencyStubPlugin(id: "terminal", name: "终端"))
        await vm.refreshMarketplace()
        guard let item2 = vm.marketplaceEntries.first(where: { $0.id == "terminal-plus" }) else {
            Issue.record("重装后市场缺少 terminal-plus 条目")
            return
        }
        #expect(item2.dependencies == ["终端"])
        #expect(item2.missingDependencies.isEmpty)
    }

    @Test("dependencySatisfied：版本满足/不满足/未安装必需/未安装可选")
    func dependencySatisfiedPure() async throws {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())
        try await manager.install(DependencyStubPlugin(id: "dep-a", name: "依赖 A"))
        let installed = await manager.list()

        let depExact = PluginDependency(id: PluginID("dep-a"), minVersion: PluginVersion(major: 1, minor: 0, patch: 0))
        let depHigher = PluginDependency(id: PluginID("dep-a"), minVersion: PluginVersion(major: 2, minor: 0, patch: 0))
        let depMissingRequired = PluginDependency(id: PluginID("dep-none"), minVersion: PluginVersion(major: 1, minor: 0, patch: 0))
        let depMissingOptional = PluginDependency(id: PluginID("dep-none"), minVersion: PluginVersion(major: 1, minor: 0, patch: 0), required: false)

        #expect(AppViewModel.dependencySatisfied(depExact, installed: installed))
        #expect(AppViewModel.dependencySatisfied(depHigher, installed: installed) == false, "1.0.0 < 2.0.0 应不满足")
        #expect(AppViewModel.dependencySatisfied(depMissingRequired, installed: installed) == false)
        #expect(AppViewModel.dependencySatisfied(depMissingOptional, installed: installed), "可选依赖未安装 = 满足")
    }

    @Test("dependencyLabel：已安装 → 展示名；未安装 → id 原文")
    func dependencyLabelPure() async throws {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())
        try await manager.install(DependencyStubPlugin(id: "dep-b", name: "依赖 B"))
        let installed = await manager.list()

        let depInstalled = PluginDependency(id: PluginID("dep-b"), minVersion: PluginVersion(major: 1, minor: 0, patch: 0))
        let depMissing = PluginDependency(id: PluginID("dep-x"), minVersion: PluginVersion(major: 1, minor: 0, patch: 0))
        #expect(AppViewModel.dependencyLabel(depInstalled, installed: installed) == "依赖 B")
        #expect(AppViewModel.dependencyLabel(depMissing, installed: installed) == "dep-x")
    }
}
