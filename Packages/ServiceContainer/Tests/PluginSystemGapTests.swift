import Foundation
@testable import ServiceContainer
import Testing

// MARK: - 覆盖审计轮 6：插件子系统薄弱分支（错误文案 / semver 预发布比较 / 协议默认 / 源去重 / 升级幂等 / AnyCodable null）

/// 计数源：统计 fetchListings 调用次数（验证 addSource 按名去重）
private actor CountingSource: PluginSource {
    let name: String
    private var fetchCount = 0

    init(name: String) {
        self.name = name
    }

    func fetchListings() async throws -> [PluginListing] {
        fetchCount += 1
        return []
    }

    func count() -> Int {
        fetchCount
    }
}

/// 最小插件：不覆写 isActive / healthCheck（走协议扩展默认实现）
private struct BarePlugin: Plugin {
    let manifest: PluginManifest

    init(id: String, version: PluginVersion) {
        manifest = PluginManifest(
            id: PluginID(id),
            name: "Bare",
            version: version,
            description: "bare plugin",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
        )
    }

    func initialize(context _: PluginContext) async throws {}
    func start(context _: PluginContext) async throws {}
    func stop(context _: PluginContext) async {}
}

private struct GapTestSource: PluginSource {
    let name: String
    let listings: [PluginListing]

    func fetchListings() async throws -> [PluginListing] {
        listings
    }
}

@Suite("PluginSystem Gap Tests")
struct PluginSystemGapTests {
    private static let harnessVersion = PluginVersion(major: 1, minor: 0, patch: 0)

    private static func makeMarketplace(sources: [any PluginSource]) -> (PluginMarketplace, PluginManager) {
        let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus(), harnessVersion: harnessVersion)
        let market = PluginMarketplace(manager: manager, harnessVersion: harnessVersion, sources: sources)
        return (market, manager)
    }

    // MARK: 错误文案

    @Test("MarketplaceError 四 case 文案")
    func marketplaceErrorDescriptions() {
        #expect(MarketplaceError.notFound(PluginID("a.b")).description
            == "Marketplace listing not found: a.b")
        #expect(MarketplaceError.alreadyInstalled(PluginID("a.b")).description
            == "Plugin already installed: a.b")
        #expect(MarketplaceError.incompatibleVersion(id: PluginID("a.b"), min: "2.0.0", current: "1.0.0").description
            == "Incompatible version for a.b: requires harness >= 2.0.0, current 1.0.0")
        #expect(MarketplaceError.fetchFailed(source: "src", reason: "timeout").description
            == "Marketplace source src fetch failed: timeout")
    }

    @Test("PluginError.versionMismatch 文案")
    func pluginErrorVersionMismatchDescription() {
        #expect(PluginError.versionMismatch(plugin: PluginID("p"), required: "1.2.0", found: "1.1.0").description
            == "Version mismatch for p: required 1.2.0, found 1.1.0")
    }

    // MARK: semver 比较

    @Test("PluginVersion 预发布比较：正式版 > 预发布；双预发布按字典序")
    func pluginVersionPrereleaseComparison() {
        let release = PluginVersion(major: 1, minor: 0, patch: 0)
        let alpha = PluginVersion(major: 1, minor: 0, patch: 0, prerelease: "alpha")
        let beta = PluginVersion(major: 1, minor: 0, patch: 0, prerelease: "beta")
        // (nil, .some) → false：正式版不小于预发布版
        #expect(!(release < alpha))
        // (.some, nil) → true：预发布版小于正式版
        #expect(alpha < release)
        // (.some, .some) → 字典序
        #expect(alpha < beta)
        #expect(!(beta < alpha))
        #expect(!(alpha < alpha))
        // 数字三元组比较优先
        #expect(PluginVersion(major: 1, minor: 2, patch: 0) < PluginVersion(major: 1, minor: 10, patch: 0))
        #expect(!(PluginVersion(major: 2, minor: 0, patch: 0) < PluginVersion(major: 1, minor: 99, patch: 99)))
    }

    // MARK: 协议默认实现

    @Test("Plugin 协议默认 isActive=false / healthCheck=unknown")
    func pluginProtocolDefaults() async {
        let plugin = BarePlugin(id: "bare", version: PluginVersion(major: 1, minor: 0, patch: 0))
        #expect(plugin.isActive == false)
        let health = await plugin.healthCheck()
        #expect(health.status == .unknown)
    }

    // MARK: 市场编排

    @Test("addSource 同名源忽略（重复注册不重复拉取）")
    func addSourceDeduplicatesByName() async {
        let (market, _) = Self.makeMarketplace(sources: [])
        let first = CountingSource(name: "a")
        let duplicate = CountingSource(name: "a")
        await market.addSource(first)
        await market.addSource(duplicate)
        await market.addSource(CountingSource(name: "b"))
        await market.refresh()
        #expect(await first.count() == 1)
        #expect(await duplicate.count() == 0, "重名源应被忽略，不进入拉取")
    }

    @Test("upgrade 已是最新版本：原样返回条目，不重装")
    func upgradeWhenAlreadyLatestReturnsEntry() async throws {
        let id = PluginID("com.harness.gap.latest")
        let version = PluginVersion(major: 1, minor: 0, patch: 0)
        let listing = PluginListing(
            id: id, name: "Latest", version: version,
            description: "already latest",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
        ) {
            BarePlugin(id: id.rawValue, version: version)
        }
        let (market, manager) = Self.makeMarketplace(
            sources: [GapTestSource(name: "a", listings: [listing])]
        )
        try await manager.install(BarePlugin(id: id.rawValue, version: version))
        await market.refresh()

        let entry = try await market.upgrade(id)
        #expect(entry.status == .installed(version: "1.0.0"))
        let info = await (manager.list()).first { $0.id == id }
        #expect(info?.state == .active)
    }

    // MARK: AnyCodable

    @Test("AnyCodable 解码 null → NSNull")
    func anyCodableDecodesNull() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: Data("null".utf8))
        #expect(decoded.value is NSNull)
    }
}
