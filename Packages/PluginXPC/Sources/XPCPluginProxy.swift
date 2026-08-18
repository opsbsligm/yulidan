import Foundation
import ServiceContainer

/// 进程内 Plugin 实现：把生命周期调用转发到 XPC worker 进程，
/// 插件崩溃只拖垮 worker，不影响主进程（崩溃隔离）
public final class XPCPluginProxy: Plugin, @unchecked Sendable {
    public let manifest: PluginManifest
    private let endpoint: any RemotePluginEndpoint
    private let pluginID: String
    private let lock = NSLock()
    private var _isActive = false

    public init(manifest: PluginManifest, endpoint: any RemotePluginEndpoint) {
        self.manifest = manifest
        self.endpoint = endpoint
        pluginID = manifest.id.rawValue
    }

    public var isActive: Bool {
        lock.withLock { _isActive }
    }

    public func initialize(context _: PluginContext) async throws {
        // initialize 与 start 合并为 worker 端一次 start 调用（XPC 无插件构造语义）
    }

    public func start(context _: PluginContext) async throws {
        let result = await withCheckedContinuation { (cont: CheckedContinuation<(Bool, String), Never>) in
            endpoint.start(pluginID: pluginID) { success, message in
                cont.resume(returning: (success, message))
            }
        }
        guard result.0 else {
            throw PluginXPCError.remoteStartFailed(pluginID, result.1)
        }
        lock.withLock { _isActive = true }
    }

    public func stop(context _: PluginContext) async {
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            endpoint.stop(pluginID: pluginID) { ok, _ in
                cont.resume(returning: ok)
            }
        }
        lock.withLock { _isActive = false }
    }

    /// worker 进程内全部插件状态
    public func remoteStatus() async -> [String: String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String: String], Never>) in
            endpoint.status { cont.resume(returning: $0) }
        }
    }

    public func healthCheck() async -> PluginHealth {
        await withCheckedContinuation { (cont: CheckedContinuation<PluginHealth, Never>) in
            endpoint.healthCheck(pluginID: pluginID) { healthy, message in
                cont.resume(returning: PluginHealth(status: healthy ? .healthy : .unhealthy, message: message))
            }
        }
    }
}

public enum PluginXPCError: Error, Sendable, CustomStringConvertible {
    case remoteStartFailed(String, String)
    case connectionLost

    public var description: String {
        switch self {
        case let .remoteStartFailed(id, reason): "Remote plugin start failed (\(id)): \(reason)"
        case .connectionLost: "XPC connection to plugin worker lost"
        }
    }
}
