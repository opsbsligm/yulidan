import Foundation

public struct PluginID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public struct PluginVersion: Sendable, Hashable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let buildMetadata: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil, buildMetadata: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    public init?(description: String) {
        let parts = description.split(separator: "+")
        let versionParts = parts[0].split(separator: "-")
        let numbers = versionParts[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        prerelease = versionParts.count > 1 ? String(versionParts[1]) : nil
        buildMetadata = parts.count > 1 ? String(parts[1]) : nil
    }

    public var description: String {
        var result = "\(major).\(minor).\(patch)"
        if let prerelease {
            result += "-\(prerelease)"
        }
        if let buildMetadata {
            result += "+\(buildMetadata)"
        }
        return result
    }
}

public struct PluginManifest: Sendable, Codable {
    public let id: PluginID
    public let name: String
    public let version: PluginVersion
    public let description: String
    public let minHarnessVersion: PluginVersion
    public let dependencies: [PluginDependency]
    public let permissions: [Permission]
    public let author: String?
    public let license: String?

    public init(
        id: PluginID,
        name: String,
        version: PluginVersion,
        description: String,
        minHarnessVersion: PluginVersion,
        dependencies: [PluginDependency] = [],
        permissions: [Permission] = [],
        author: String? = nil,
        license: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.minHarnessVersion = minHarnessVersion
        self.dependencies = dependencies
        self.permissions = permissions
        self.author = author
        self.license = license
    }
}

public struct PluginDependency: Sendable, Codable {
    public let id: PluginID
    public let minVersion: PluginVersion
    public let maxVersion: PluginVersion?
    public let required: Bool

    public init(id: PluginID, minVersion: PluginVersion, maxVersion: PluginVersion? = nil, required: Bool = true) {
        self.id = id
        self.minVersion = minVersion
        self.maxVersion = maxVersion
        self.required = required
    }
}

public enum Permission: String, Sendable, Codable, CaseIterable {
    case filesystemRead, filesystemWrite, shellExecution, networkAccess
    case subprocessSpawn, terminalAccess, clipboardAccess, screenCapture, keychainAccess

    public var level: PermissionLevel {
        switch self {
        case .filesystemRead, .clipboardAccess: .low
        case .filesystemWrite, .networkAccess, .keychainAccess: .medium
        case .shellExecution, .subprocessSpawn, .terminalAccess, .screenCapture: .high
        }
    }
}

public enum PermissionLevel: Int, Sendable, Codable {
    case low = 1, medium = 2, high = 3
}

public protocol Plugin: Sendable {
    var manifest: PluginManifest { get }
    var isActive: Bool { get }
    func initialize(context: PluginContext) async throws
    func start(context: PluginContext) async throws
    func stop(context: PluginContext) async
    func healthCheck() async -> PluginHealth
}

public struct PluginHealth: Sendable, Codable {
    public let status: HealthStatus
    public let message: String?
    public let timestamp: Date
    public let metrics: [String: Double]

    public enum HealthStatus: String, Sendable, Codable {
        case healthy, degraded, unhealthy, unknown
    }

    public init(status: HealthStatus, message: String? = nil, metrics: [String: Double] = [:]) {
        self.status = status
        self.message = message
        timestamp = Date()
        self.metrics = metrics
    }
}

public extension Plugin {
    var isActive: Bool {
        false
    }

    func healthCheck() async -> PluginHealth {
        PluginHealth(status: .unknown)
    }
}
