import Foundation
@testable import ServiceContainer
import Testing

// MARK: - P0.4 ⑥ 主题插件机制（ServiceContainer 层）：ThemeSpec 数据形状 + activePluginInstances

private final class ThemeProviderStub: Plugin, ThemeProviderPlugin, @unchecked Sendable {
    var manifest: PluginManifest
    var isActive: Bool = false

    init(id: String = "com.harness.theme", name: String = "Theme") {
        manifest = PluginManifest(
            id: PluginID(id), name: name,
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "Test theme",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
        )
    }

    let themeSpec = ThemeSpec(
        id: "stub-theme", name: "测试主题",
        accentHex: "#112233", userMessageHex: "#11223326", assistantMessageHex: "#11223314"
    )

    func initialize(context _: PluginContext) async throws {}
    func start(context _: PluginContext) async throws {
        isActive = true
    }

    func stop(context _: PluginContext) async {
        isActive = false
    }
}

private final class PlainStub: Plugin, @unchecked Sendable {
    var manifest: PluginManifest
    var isActive: Bool = false

    init(id: String = "com.harness.plain") {
        manifest = PluginManifest(
            id: PluginID(id), name: "Plain",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
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

@Suite("P0.4 主题插件（ServiceContainer）")
struct ThemeTests {
    // MARK: ThemeSpec 数据形状

    @Test("systemBaseline 全 nil = 回落基准")
    func systemBaselineAllNil() {
        #expect(ThemeSpec.systemBaseline.id == "system-baseline")
        #expect(ThemeSpec.systemBaseline.accentHex == nil)
        #expect(ThemeSpec.systemBaseline.userMessageHex == nil)
        #expect(ThemeSpec.systemBaseline.assistantMessageHex == nil)
        #expect(ThemeSpec.systemBaseline.glassTintHex == nil)
        #expect(ThemeSpec.systemBaseline.blurIntensity == nil)
        #expect(ThemeSpec.systemBaseline.highlightIntensity == nil)
    }

    @Test("ThemeSpec Codable 往返（含 P1 预留玻璃字段）")
    func codableRoundTrip() throws {
        let spec = ThemeSpec(
            id: "x", name: "X", accentHex: "#AABBCC",
            userMessageHex: "#AABBCC26", assistantMessageHex: "#AABBCC14",
            description: "desc", glassTintHex: "#123456",
            blurIntensity: 0.4, highlightIntensity: 0.8
        )
        let data = try JSONEncoder().encode(spec)
        let back = try JSONDecoder().decode(ThemeSpec.self, from: data)
        #expect(back == spec)
        // 省略可选字段可解码（兼容最小 JSON 的主题服务器）
        let minimal = #"{"id":"m","name":"M"}"#
        let decoded = try JSONDecoder().decode(ThemeSpec.self, from: Data(minimal.utf8))
        #expect(decoded.id == "m")
        #expect(decoded.accentHex == nil)
        // 未知字段忽略（前向兼容）
        let extra = #"{"id":"m","name":"M","futureField":1}"#
        #expect(try JSONDecoder().decode(ThemeSpec.self, from: Data(extra.utf8)).id == "m")
    }

    // MARK: activePluginInstances

    @Test("activePluginInstances 仅返回 active 实例且可向下转型")
    func activeInstances() async throws {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())
        let theme = ThemeProviderStub()
        let plain = PlainStub()
        try await manager.install(theme)
        try await manager.install(plain)

        let instances = await manager.activePluginInstances()
        #expect(instances.count == 2)
        // App 层按 ThemeProviderPlugin 过滤的逻辑在容器层可用
        let themes = instances.compactMap { $0 as? ThemeProviderPlugin }
        #expect(themes.count == 1)
        #expect(themes.first?.themeSpec.id == "stub-theme")
        #expect(themes.first?.manifest.id.rawValue == "com.harness.theme")

        // 卸载后不再出现
        try await manager.uninstall(theme.manifest.id)
        let after = await manager.activePluginInstances()
        #expect(after.count == 1)
        #expect(after.first as? ThemeProviderPlugin == nil)
    }
}
