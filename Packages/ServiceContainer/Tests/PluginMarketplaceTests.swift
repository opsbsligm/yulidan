import Foundation
@testable import ServiceContainer
import Testing

// MARK: - 测试替身

private final class MktTestPlugin: Plugin, @unchecked Sendable {
    var manifest: PluginManifest
    var isActive: Bool = false

    init(
        id: String,
        name: String,
        version: PluginVersion = PluginVersion(major: 1, minor: 0, patch: 0),
        minHarness: PluginVersion = PluginVersion(major: 0, minor: 1, patch: 0),
        permissions: [Permission] = [],
        dependencies: [PluginDependency] = []
    ) {
        manifest = PluginManifest(
            id: PluginID(id),
            name: name,
            version: version,
            description: "Description of \(name)",
            minHarnessVersion: minHarness,
            dependencies: dependencies,
            permissions: permissions
        )
    }

    func initialize(context _: PluginContext) async throws {}
    func start(context _: PluginContext) async {
        isActive = true
    }

    func stop(context _: PluginContext) async {
        isActive = false
    }
}

private enum MktStartError: Error, Sendable { case failure }

/// 通过共享门控决定是否在 start 时失败，用于模拟安装失败后的重试
private actor FailGate {
    var shouldFail = false
    func setFail(_ fail: Bool) {
        shouldFail = fail
    }
}

private final class FailingStartPlugin: Plugin, @unchecked Sendable {
    let manifest: PluginManifest
    private let gate: FailGate
    var isActive: Bool = false

    init(id: String, gate: FailGate) {
        manifest = PluginManifest(
            id: PluginID(id),
            name: "Failing",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "Always fails on start unless gate says otherwise",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
        )
        self.gate = gate
    }

    func initialize(context _: PluginContext) async throws {}
    func start(context _: PluginContext) async throws {
        if await gate.shouldFail {
            throw MktStartError.failure
        }
        isActive = true
    }

    func stop(context _: PluginContext) async {
        isActive = false
    }
}

private actor TestSource: PluginSource {
    let name: String
    private var listings: [PluginListing]

    init(name: String, listings: [PluginListing] = []) {
        self.name = name
        self.listings = listings
    }

    func setListings(_ new: [PluginListing]) {
        listings = new
    }

    func fetchListings() async throws -> [PluginListing] {
        listings
    }
}

// MARK: - 工厂辅助

private func makeListing(
    id: String = "com.harness.mkt.test",
    name: String = "Test Plugin",
    version: PluginVersion = PluginVersion(major: 1, minor: 0, patch: 0),
    minHarness: PluginVersion = PluginVersion(major: 0, minor: 1, patch: 0),
    permissions: [Permission] = [],
    dependencies: [PluginDependency] = []
) -> PluginListing {
    PluginListing(
        id: PluginID(id),
        name: name,
        version: version,
        description: "Description of \(name)",
        permissions: permissions,
        minHarnessVersion: minHarness,
        dependencies: dependencies
    ) {
        MktTestPlugin(id: id, name: name, version: version, minHarness: minHarness, permissions: permissions, dependencies: dependencies)
    }
}

private func makeMarketplace(
    sources: [any PluginSource] = [],
    harnessVersion: PluginVersion = PluginVersion(major: 1, minor: 0, patch: 0)
) -> (market: PluginMarketplace, manager: PluginManager) {
    let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus(), harnessVersion: harnessVersion)
    let market = PluginMarketplace(manager: manager, harnessVersion: harnessVersion, sources: sources)
    return (market, manager)
}

// MARK: - 测试

@Suite("PluginMarketplace Tests")
struct PluginMarketplaceTests {
    @Test("Browse merges multiple sources sorted by id")
    func browseMergesSources() async {
        let (market, _) = makeMarketplace(sources: [
            TestSource(name: "a", listings: [makeListing(id: "com.harness.zeta"), makeListing(id: "com.harness.alpha")]),
            TestSource(name: "b", listings: [makeListing(id: "com.harness.beta")]),
        ])
        await market.refresh()
        let entries = await market.browse()
        let ids = entries.map(\.listing.id.rawValue)
        #expect(ids == ["com.harness.alpha", "com.harness.beta", "com.harness.zeta"])
        #expect(entries.allSatisfy { $0.status == .notInstalled })
    }

    @Test("Duplicate id: first registered source wins")
    func firstSourceWins() async {
        let (market, _) = makeMarketplace(sources: [
            TestSource(name: "a", listings: [makeListing(id: "com.harness.dup", name: "From A")]),
            TestSource(name: "b", listings: [makeListing(id: "com.harness.dup", name: "From B")]),
        ])
        await market.refresh()
        let entry = await market.entry(for: PluginID("com.harness.dup"))
        #expect(entry?.listing.name == "From A")
    }

    @Test("Search matches name description and id case-insensitively")
    func search() async {
        let (market, _) = makeMarketplace(sources: [
            TestSource(name: "a", listings: [
                makeListing(id: "com.harness.alpha", name: "Alpha Tool"),
                makeListing(id: "com.harness.beta", name: "Beta Net"),
                makeListing(id: "com.harness.gamma", name: "Gamma"),
            ]),
        ])
        await market.refresh()

        let byName = await market.search("ALPHA")
        #expect(byName.map(\.listing.id.rawValue) == ["com.harness.alpha"])

        let byDesc = await market.search("description of gamma")
        #expect(byDesc.count == 1)

        let byId = await market.search("harness.BETA")
        #expect(byId.map(\.listing.id.rawValue) == ["com.harness.beta"])

        let all = await market.search("   ")
        #expect(all.count == 3)
    }

    @Test("Install from marketplace activates plugin")
    func install() async throws {
        let (market, manager) = makeMarketplace(sources: [TestSource(name: "a", listings: [makeListing()])])
        await market.refresh()

        let entry = try await market.install(PluginID("com.harness.mkt.test"))
        #expect(await manager.isActive(PluginID("com.harness.mkt.test")))
        #expect(entry.status == .installed(version: "1.0.0"))

        let refreshed = await market.entry(for: PluginID("com.harness.mkt.test"))
        #expect(refreshed?.isInstalled == true)
    }

    @Test("Install already installed plugin throws")
    func installAlreadyInstalled() async throws {
        let (market, _) = makeMarketplace(sources: [TestSource(name: "a", listings: [makeListing()])])
        await market.refresh()
        let id = PluginID("com.harness.mkt.test")
        _ = try await market.install(id)
        do {
            _ = try await market.install(id)
            Issue.record("Expected alreadyInstalled error")
        } catch let error as MarketplaceError {
            guard case let .alreadyInstalled(found) = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
            #expect(found == id)
        }
    }

    @Test("Incompatible harness version blocks install")
    func incompatible() async throws {
        let (market, _) = makeMarketplace(
            sources: [TestSource(name: "a", listings: [makeListing(minHarness: PluginVersion(major: 2, minor: 0, patch: 0))])]
        )
        await market.refresh()
        let id = PluginID("com.harness.mkt.test")

        let entry = await market.entry(for: id)
        #expect(entry?.status == .incompatible(reason: "requires harness >= 2.0.0, current 1.0.0"))

        do {
            _ = try await market.install(id)
            Issue.record("Expected incompatibleVersion error")
        } catch let error as MarketplaceError {
            guard case .incompatibleVersion = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
        }
    }

    @Test("Failed start leaves retryable state and reinstall succeeds")
    func retryAfterFailure() async throws {
        let gate = FailGate()
        await gate.setFail(true)
        let failing = FailingStartPlugin(id: "com.harness.failing", gate: gate)
        let listing = PluginListing(plugin: failing)
        let (market, manager) = makeMarketplace(sources: [TestSource(name: "a", listings: [listing])])
        await market.refresh()
        let id = PluginID("com.harness.failing")

        do {
            _ = try await market.install(id)
            Issue.record("Expected start failure")
        } catch {}

        // 失败残留被清理，放开门控后可重装
        await gate.setFail(false)
        let entry = try await market.install(id)
        #expect(entry.status == .installed(version: "1.0.0"))
        #expect(await manager.isActive(id))
    }

    @Test("Upgrade moves installed plugin to catalog version")
    func upgrade() async throws {
        let source = TestSource(name: "a", listings: [makeListing(version: PluginVersion(major: 1, minor: 0, patch: 0))])
        let (market, manager) = makeMarketplace(sources: [source])
        await market.refresh()
        let id = PluginID("com.harness.mkt.test")

        _ = try await market.install(id)

        // 目录更新到 1.1.0
        await source.setListings([makeListing(version: PluginVersion(major: 1, minor: 1, patch: 0))])
        await market.refresh()
        let stale = await market.entry(for: id)
        #expect(stale?.hasUpdate == true)

        let upgraded = try await market.upgrade(id)
        #expect(upgraded.status == .installed(version: "1.1.0"))
        #expect(await manager.isActive(id))
        let after = await market.entry(for: id)
        #expect(after?.hasUpdate == false)
    }

    @Test("Upgrade when not installed behaves like install")
    func upgradeNotInstalled() async throws {
        let (market, manager) = makeMarketplace(sources: [TestSource(name: "a", listings: [makeListing()])])
        await market.refresh()
        let id = PluginID("com.harness.mkt.test")
        _ = try await market.upgrade(id)
        #expect(await manager.isActive(id))
    }

    @Test("Uninstall via marketplace returns entry to notInstalled")
    func uninstall() async throws {
        let (market, manager) = makeMarketplace(sources: [TestSource(name: "a", listings: [makeListing()])])
        await market.refresh()
        let id = PluginID("com.harness.mkt.test")
        _ = try await market.install(id)

        try await market.uninstall(id)
        #expect(await manager.isActive(id) == false)
        let entry = await market.entry(for: id)
        #expect(entry?.status == .notInstalled)
    }

    @Test("Missing required dependency blocks install until dependency present")
    func missingDependency() async throws {
        let dep = makeListing(id: "com.harness.dep", name: "Dep")
        let main = makeListing(
            id: "com.harness.main",
            name: "Main",
            dependencies: [PluginDependency(id: PluginID("com.harness.dep"), minVersion: PluginVersion(major: 1, minor: 0, patch: 0))]
        )
        let (market, _) = makeMarketplace(sources: [TestSource(name: "a", listings: [dep, main])])
        await market.refresh()

        do {
            _ = try await market.install(PluginID("com.harness.main"))
            Issue.record("Expected missingDependency error")
        } catch let error as PluginError {
            guard case let .missingDependency(found) = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
            #expect(found == PluginID("com.harness.dep"))
        }

        _ = try await market.install(PluginID("com.harness.dep"))
        let entry = try await market.install(PluginID("com.harness.main"))
        #expect(entry.status == .installed(version: "1.0.0"))
    }

    @Test("High risk entries expose high-level permission requests")
    func highRisk() async {
        let (market, _) = makeMarketplace(sources: [
            TestSource(name: "a", listings: [
                makeListing(id: "com.harness.safe", name: "Safe", permissions: [.filesystemRead]),
                makeListing(id: "com.harness.risky", name: "Risky", permissions: [.shellExecution]),
            ]),
        ])
        await market.refresh()
        let risky = await market.highRiskEntries()
        #expect(risky.map(\.listing.id.rawValue) == ["com.harness.risky"])
    }

    @Test("Remove source drops its listings on refresh")
    func removeSource() async {
        let (market, _) = makeMarketplace(sources: [
            TestSource(name: "a", listings: [makeListing(id: "com.harness.only-a")]),
            TestSource(name: "b", listings: [makeListing(id: "com.harness.only-b")]),
        ])
        await market.refresh()
        #expect(await (market.browse()).count == 2)

        await market.removeSource(named: "a")
        let ids = await (market.browse()).map(\.listing.id.rawValue)
        #expect(ids == ["com.harness.only-b"])
    }

    @Test("Refresh skips failing source and keeps healthy ones")
    func failingSourceSkipped() async throws {
        struct FailingSource: PluginSource {
            let name = "broken"
            func fetchListings() async throws -> [PluginListing] {
                throw MktStartError.failure
            }
        }
        let (market, _) = makeMarketplace(sources: [
            FailingSource(),
            TestSource(name: "ok", listings: [makeListing()]),
        ])
        let count = await market.refresh()
        #expect(count == 1)
        #expect(await (market.browse()).count == 1)
    }
}
