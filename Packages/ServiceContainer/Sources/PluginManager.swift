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

    init(entry: PluginEntry) {
        id = entry.manifest.id
        name = entry.manifest.name
        version = entry.manifest.version.description
        state = entry.state
        startedAt = entry.startedAt
        stoppedAt = entry.stoppedAt
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

        guard entry.state == .active, let context = entry.context else { return }

        entry.state = .stopping
        await entry.plugin.stop(context: context)
        entry.state = .stopped
        entry.stoppedAt = Date()

        for effect in entry.effects.reversed() {
            effect.dispose()
        }

        plugins.removeValue(forKey: pluginID)
    }

    public func list() -> [PluginInfo] {
        plugins.values.map { PluginInfo(entry: $0) }
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

    private func checkPermissions(_ manifest: PluginManifest) throws {
        let highPerms = manifest.permissions.filter { $0.level == .high }
        if !highPerms.isEmpty {
            logger.warning("Plugin \(manifest.id.rawValue) requests high-level permissions")
        }
    }
}
