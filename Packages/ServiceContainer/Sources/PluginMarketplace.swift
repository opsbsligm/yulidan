import Foundation
import os.log

// MARK: - 目录源

/// 插件目录源：提供一组可安装的插件清单。可接入本地目录、远程仓库、打包分发等任意来源，
/// 多个源可聚合到同一个市场（同 id 冲突时先注册的源优先）。
public protocol PluginSource: Sendable {
    /// 源显示名（用于去重与日志）
    var name: String { get }
    func fetchListings() async throws -> [PluginListing]
}

// MARK: - 清单条目

/// 市场清单条目：描述一个可安装插件，并持有工厂闭包在真正安装时实例化插件对象。
public struct PluginListing: Sendable {
    public let id: PluginID
    public let name: String
    public let version: PluginVersion
    public let description: String
    public let author: String?
    public let permissions: [Permission]
    public let minHarnessVersion: PluginVersion
    public let dependencies: [PluginDependency]
    /// 插件工厂：安装时才实例化，避免目录拉取就构造全部插件
    public let make: @Sendable () -> any Plugin

    public init(
        id: PluginID,
        name: String,
        version: PluginVersion,
        description: String,
        author: String? = nil,
        permissions: [Permission] = [],
        minHarnessVersion: PluginVersion = PluginVersion(major: 0, minor: 1, patch: 0),
        dependencies: [PluginDependency] = [],
        make: @escaping @Sendable () -> any Plugin
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.permissions = permissions
        self.minHarnessVersion = minHarnessVersion
        self.dependencies = dependencies
        self.make = make
    }

    /// 把现有插件实例包装为清单（用于内置/本地插件上架）
    public init(plugin: any Plugin) {
        let manifest = plugin.manifest
        self.init(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            author: manifest.author,
            permissions: manifest.permissions,
            minHarnessVersion: manifest.minHarnessVersion,
            dependencies: manifest.dependencies,
            make: { plugin }
        )
    }
}

// MARK: - 市场条目（清单 + 安装状态）

public struct MarketplaceEntry: Sendable {
    public let listing: PluginListing
    public let status: Status

    public enum Status: Sendable, Equatable {
        case notInstalled
        case installed(version: String)
        case incompatible(reason: String)
    }

    public init(listing: PluginListing, status: Status) {
        self.listing = listing
        self.status = status
    }

    public var isInstalled: Bool {
        if case .installed = status {
            return true
        }
        return false
    }

    /// 已安装且目录版本比本地新（PluginVersion 可按 semver 比较）
    public var hasUpdate: Bool {
        guard case let .installed(installedVersion) = status,
              let installed = PluginVersion(description: installedVersion)
        else { return false }
        return installed < listing.version
    }
}

// MARK: - 错误

public enum MarketplaceError: Error, Sendable, CustomStringConvertible {
    case notFound(PluginID)
    case alreadyInstalled(PluginID)
    case incompatibleVersion(id: PluginID, min: String, current: String)
    case fetchFailed(source: String, reason: String)

    public var description: String {
        switch self {
        case let .notFound(id):
            "Marketplace listing not found: \(id.rawValue)"
        case let .alreadyInstalled(id):
            "Plugin already installed: \(id.rawValue)"
        case let .incompatibleVersion(id, min, current):
            "Incompatible version for \(id.rawValue): requires harness >= \(min), current \(current)"
        case let .fetchFailed(source, reason):
            "Marketplace source \(source) fetch failed: \(reason)"
        }
    }
}

// MARK: - 市场

/// 插件市场：聚合多个目录源，提供浏览/搜索/安装/升级/卸载。
/// 实际的安装生命周期仍由 PluginManager 负责，市场只负责目录与编排。
public actor PluginMarketplace {
    private let manager: PluginManager
    private let harnessVersion: PluginVersion
    private let logger: Logger
    private var sources: [any PluginSource]
    private var cache: [PluginID: PluginListing] = [:]

    public init(manager: PluginManager, harnessVersion: PluginVersion, sources: [any PluginSource] = []) {
        self.manager = manager
        self.harnessVersion = harnessVersion
        self.sources = sources
        logger = Logger(subsystem: "com.harness", category: "plugin.marketplace")
    }

    // MARK: 源管理

    public func addSource(_ source: any PluginSource) {
        guard !sources.contains(where: { $0.name == source.name }) else { return }
        sources.append(source)
    }

    public func removeSource(named name: String) async {
        sources.removeAll { $0.name == name }
        await refresh()
    }

    /// 按注册顺序从所有源拉取最新目录并合并缓存；单源失败只告警不中断，
    /// 同 id 冲突时先注册的源优先。返回合并后的条目总数。
    @discardableResult
    public func refresh() async -> Int {
        var merged: [PluginID: PluginListing] = [:]
        for source in sources {
            let fetched: [PluginListing]
            do {
                fetched = try await source.fetchListings()
            } catch {
                logger.warning("Marketplace source \(source.name) fetch failed: \(error.localizedDescription)")
                continue
            }
            for listing in fetched where merged[listing.id] == nil {
                merged[listing.id] = listing
            }
        }
        cache = merged
        return merged.count
    }

    // MARK: 浏览与搜索

    /// 全部目录条目（按 id 字典序），附带安装状态
    public func browse() async -> [MarketplaceEntry] {
        let installed = await installedMap()
        return cache.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { makeEntry(listing: $0, info: installed[$0.id]) }
    }

    /// 按名称/描述/id 不区分大小写搜索；空查询返回全部
    public func search(_ query: String) async -> [MarketplaceEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let entries = await browse()
        guard !normalized.isEmpty else { return entries }
        return entries.filter { entry in
            entry.listing.name.lowercased().contains(normalized)
                || entry.listing.description.lowercased().contains(normalized)
                || entry.listing.id.rawValue.lowercased().contains(normalized)
        }
    }

    public func entry(for id: PluginID) async -> MarketplaceEntry? {
        guard let listing = cache[id] else { return nil }
        let info = await (manager.list()).first { $0.id == id }
        return makeEntry(listing: listing, info: info)
    }

    /// 请求 high 级权限（shell/终端/截屏等）的条目，供 UI 做权限门槛提示
    public func highRiskEntries() async -> [MarketplaceEntry] {
        let entries = await browse()
        return entries.filter { $0.listing.permissions.contains { $0.level == .high } }
    }

    // MARK: 安装 / 卸载 / 升级

    /// 安装市场插件：兼容检查 → 工厂实例化 → 交给 PluginManager 走完整生命周期
    @discardableResult
    public func install(_ id: PluginID) async throws -> MarketplaceEntry {
        guard let listing = cache[id] else { throw MarketplaceError.notFound(id) }

        if let info = await manager.list().first(where: { $0.id == id }) {
            if info.state == .active {
                throw MarketplaceError.alreadyInstalled(id)
            }
            // 清理非 active 残留（如安装失败），允许重试
            try await manager.uninstall(id)
        }

        guard listing.minHarnessVersion <= harnessVersion else {
            throw MarketplaceError.incompatibleVersion(
                id: id,
                min: listing.minHarnessVersion.description,
                current: harnessVersion.description
            )
        }

        let plugin = listing.make()
        try await manager.install(plugin)
        return try await requireEntry(id)
    }

    public func uninstall(_ id: PluginID) async throws {
        try await manager.uninstall(id)
    }

    /// 升级到目录最新版本；未安装视为安装，已是最新则原样返回
    @discardableResult
    public func upgrade(_ id: PluginID) async throws -> MarketplaceEntry {
        guard let listing = cache[id] else { throw MarketplaceError.notFound(id) }
        guard let info = await manager.list().first(where: { $0.id == id }) else {
            return try await install(id)
        }
        if let installed = PluginVersion(description: info.version), installed >= listing.version {
            return try await requireEntry(id)
        }
        try await manager.uninstall(id)
        return try await install(id)
    }

    // MARK: 私有

    private func installedMap() async -> [PluginID: PluginInfo] {
        await (manager.list()).reduce(into: [:]) { $0[$1.id] = $1 }
    }

    private func makeEntry(listing: PluginListing, info: PluginInfo?) -> MarketplaceEntry {
        let status: MarketplaceEntry.Status = if let info {
            .installed(version: info.version)
        } else if listing.minHarnessVersion > harnessVersion {
            .incompatible(reason: "requires harness >= \(listing.minHarnessVersion), current \(harnessVersion)")
        } else {
            .notInstalled
        }
        return MarketplaceEntry(listing: listing, status: status)
    }

    private func requireEntry(_ id: PluginID) async throws -> MarketplaceEntry {
        guard let entry = await entry(for: id) else { throw MarketplaceError.notFound(id) }
        return entry
    }
}
