import Foundation
import os.log

public enum PluginState: String, Sendable, Codable {
    case loading, initializing, starting, active, stopping, stopped, failed, errored
}

public enum PluginError: Error, Sendable, CustomStringConvertible {
    case notFound(PluginID)
    case alreadyInstalled(PluginID)
    case missingDependency(PluginID)
    case versionMismatch(plugin: PluginID, required: String, found: String)
    case permissionDenied(PluginID, [Permission])
    case initializationFailed(PluginID, Error)
    case startFailed(PluginID, Error)
    case stopFailed(PluginID, Error)
    case incompatibleVersion(PluginID, minVersion: String, currentVersion: String)

    public var description: String {
        switch self {
        case let .notFound(id): "Plugin not found: \(id.rawValue)"
        case let .alreadyInstalled(id): "Plugin already installed: \(id.rawValue)"
        case let .missingDependency(id): "Missing dependency: \(id.rawValue)"
        case let .versionMismatch(plugin, required, found):
            "Version mismatch for \(plugin.rawValue): required \(required), found \(found)"
        case let .permissionDenied(id, perms):
            "Permission denied for \(id.rawValue): \(perms.map(\.rawValue))"
        case let .initializationFailed(id, error):
            "Initialization failed for \(id.rawValue): \(error.localizedDescription)"
        case let .startFailed(id, error):
            "Start failed for \(id.rawValue): \(error.localizedDescription)"
        case let .stopFailed(id, error):
            "Stop failed for \(id.rawValue): \(error.localizedDescription)"
        case let .incompatibleVersion(id, min, current):
            "Incompatible version for \(id.rawValue): requires \(min), found \(current)"
        }
    }
}

public struct PluginInfo: Sendable {
    public let id: PluginID
    public let name: String
    public let version: String
    public let state: PluginState
    public let startedAt: Date?
    public let stoppedAt: Date?
    /// manifest 声明的真实权限（P0.4 权限门禁 UI 数据源；不再依赖 App 层硬编码目录）
    public let permissions: [Permission]

    init(entry: PluginEntry) {
        id = entry.manifest.id
        name = entry.manifest.name
        version = entry.manifest.version.description
        state = entry.state
        startedAt = entry.startedAt
        stoppedAt = entry.stoppedAt
        permissions = entry.manifest.permissions
    }
}

struct PluginEntry: @unchecked Sendable {
    let plugin: any Plugin
    let manifest: PluginManifest
    var state: PluginState
    var context: PluginContext?
    var effects: [Effect]
    var startedAt: Date?
    var stoppedAt: Date?

    init(plugin: any Plugin, manifest: PluginManifest, state: PluginState = .loading) {
        self.plugin = plugin
        self.manifest = manifest
        self.state = state
        context = nil
        effects = []
        startedAt = nil
        stoppedAt = nil
    }
}

public actor PluginManager {
    private var plugins: [PluginID: PluginEntry] = [:]
    /// 权限授予状态（P0.4 门禁：中/高危权限须显式授予后安装；内存态与插件子系统同生命周期，每次启动重新裁决）
    private var grantedPermissions: [PluginID: Set<Permission>] = [:]
    private let container: ServiceContainer
    private let eventBus: EventBus
    private let logger: Logger
    private var harnessVersion: PluginVersion

    public init(
        container: ServiceContainer,
        eventBus: EventBus,
        harnessVersion: PluginVersion = PluginVersion(major: 0, minor: 1, patch: 0)
    ) {
        self.container = container
        self.eventBus = eventBus
        logger = Logger(subsystem: "com.harness", category: "plugin.manager")
        self.harnessVersion = harnessVersion
    }

    public func install(_ plugin: any Plugin, configuration: PluginConfiguration = PluginConfiguration()) async throws {
        let manifest = plugin.manifest

        guard plugins[manifest.id] == nil else {
            throw PluginError.alreadyInstalled(manifest.id)
        }

        try checkVersionCompatibility(manifest)
        try checkDependencies(manifest)
        try checkPermissions(manifest)

        let cancellation = Cancellation()
        let context = PluginContext(
            container: container,
            eventBus: eventBus,
            configuration: configuration,
            logger: .pluginLogger(pluginID: manifest.id),
            cancellation: cancellation
        )

        var entry = PluginEntry(plugin: plugin, manifest: manifest, state: .initializing)
        entry.context = context
        entry.state = .initializing

        do {
            try await plugin.initialize(context: context)
            entry.state = .starting
        } catch {
            entry.state = .failed
            plugins[manifest.id] = entry
            throw PluginError.initializationFailed(manifest.id, error)
        }

        do {
            try await plugin.start(context: context)
            entry.state = .active
            entry.startedAt = Date()
        } catch {
            entry.state = .failed
            plugins[manifest.id] = entry
            throw PluginError.startFailed(manifest.id, error)
        }

        plugins[manifest.id] = entry
        logger.info("Plugin installed: \(manifest.name) v\(manifest.version)")
    }

    public func uninstall(_ pluginID: PluginID) async throws {
        guard var entry = plugins[pluginID] else {
            throw PluginError.notFound(pluginID)
        }

        // 仅对 active 插件执行 stop 生命周期；非 active（如初始化/启动失败）残留条目直接清理，
        // 否则失败插件会永远阻塞重装
        if entry.state == .active, let context = entry.context {
            entry.state = .stopping
            await entry.plugin.stop(context: context)
        }
        entry.state = .stopped
        entry.stoppedAt = Date()

        for effect in entry.effects.reversed() {
            effect.dispose()
        }

        revokePermissions(pluginID)
        plugins.removeValue(forKey: pluginID)
    }

    public func list() -> [PluginInfo] {
        plugins.values.map { PluginInfo(entry: $0) }
    }

    /// active 插件实例快照（供能力探测，如主题插件发现；只读，不改变生命周期）
    public func activePluginInstances() -> [any Plugin] {
        plugins.values.filter { $0.state == .active }.map(\.plugin)
    }

    public func activePlugins() -> [PluginInfo] {
        plugins.values.filter { $0.state == .active }.map { PluginInfo(entry: $0) }
    }

    public func isActive(_ id: PluginID) -> Bool {
        plugins[id]?.state == .active
    }

    public func stopAll() async {
        for (_, entry) in plugins where entry.state == .active {
            if let context = entry.context {
                await entry.plugin.stop(context: context)
            }
        }
        plugins.removeAll()
    }

    private func checkVersionCompatibility(_ manifest: PluginManifest) throws {
        if manifest.minHarnessVersion.major > harnessVersion.major {
            throw PluginError.incompatibleVersion(
                manifest.id,
                minVersion: manifest.minHarnessVersion.description,
                currentVersion: harnessVersion.description
            )
        }
    }

    private func checkDependencies(_ manifest: PluginManifest) throws {
        for dep in manifest.dependencies {
            guard plugins[dep.id] != nil || !dep.required else {
                throw PluginError.missingDependency(dep.id)
            }
        }
    }

    // MARK: - 权限门禁（P0.4：授予 / 拒绝 / 撤销）

    /// 授予插件权限（安装前调用；permissionDenied 后用户裁决「授予」再重试安装）
    public func grantPermissions(_ id: PluginID, _ permissions: [Permission]) {
        grantedPermissions[id, default: []].formUnion(permissions)
    }

    /// 撤销插件全部授予（卸载时清理，防残留授予）
    public func revokePermissions(_ id: PluginID) {
        grantedPermissions[id] = nil
    }

    /// 查询插件当前已授予权限（UI 展示「已授予」标记）
    public func grantedPermissions(for id: PluginID) -> Set<Permission> {
        grantedPermissions[id] ?? []
    }

    private func checkPermissions(_ manifest: PluginManifest) throws {
        // P0.4 门禁：low 风险权限放行；medium/high 须事先显式授予，否则抛 permissionDenied 走 UI 裁决
        let ungranted = manifest.permissions.filter {
            $0.level != .low && !grantedPermissions[manifest.id, default: []].contains($0)
        }
        guard ungranted.isEmpty else {
            logger.info("Plugin \(manifest.id.rawValue) 请求未授权权限：\(ungranted.map(\.rawValue))")
            throw PluginError.permissionDenied(manifest.id, ungranted)
        }
    }
}
