import Foundation
import HarnessCore
import PluginXPC
import ServiceContainer

/// XPC reply 闭包不是 Sendable；XPC reply 本身线程安全，用 @unchecked 盒桥接到 Task
private struct ReplyBox<T: Sendable>: @unchecked Sendable {
    let send: (T) -> Void
    init(_ send: @escaping (T) -> Void) {
        self.send = send
    }
}

/// XPC 插件 worker：在独立进程中运行内置插件，实现崩溃隔离。
/// 由 launchd（launchctl submit）按需拉起，监听 XPCPluginHost.serviceName。
final class WorkerEndpoint: NSObject, RemotePluginEndpoint, @unchecked Sendable {
    private let manager = PluginManager(container: ServiceContainer(), eventBus: EventBus())

    private func makePlugin(_ id: String) -> (any Plugin)? {
        switch id {
        case "file-system": BuiltInFilesystemPlugin()
        case "terminal": BuiltInTerminalPlugin()
        default: nil
        }
    }

    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func start(pluginID: String, reply: @escaping (Bool, String) -> Void) {
        guard let plugin = makePlugin(pluginID) else {
            reply(false, "unknown plugin: \(pluginID)")
            return
        }
        let box = ReplyBox { (ok: Bool, message: String) in
            reply(ok, message)
        }
        let manager = manager
        Task {
            do {
                // 内置插件 = 系统预授予（与主进程 installBuiltInPlugins 口径一致；P0.4 门禁免裁决）
                await manager.grantPermissions(plugin.manifest.id, plugin.manifest.permissions)
                try await manager.install(plugin)
                box.send((true, "ok"))
            } catch {
                box.send((false, error.localizedDescription))
            }
        }
    }

    func stop(pluginID: String, reply: @escaping (Bool, String) -> Void) {
        let box = ReplyBox { (ok: Bool, message: String) in
            reply(ok, message)
        }
        let manager = manager
        Task {
            do {
                try await manager.uninstall(PluginID(pluginID))
                box.send((true, "ok"))
            } catch {
                box.send((false, error.localizedDescription))
            }
        }
    }

    func status(reply: @escaping ([String: String]) -> Void) {
        let box = ReplyBox { (map: [String: String]) in
            reply(map)
        }
        let manager = manager
        Task {
            let infos = await manager.list()
            box.send(Dictionary(uniqueKeysWithValues: infos.map { ($0.id.rawValue, $0.state.rawValue) }))
        }
    }

    func healthCheck(pluginID: String, reply: @escaping (Bool, String?) -> Void) {
        let box = ReplyBox { (result: (Bool, String?)) in
            reply(result.0, result.1)
        }
        let manager = manager
        Task {
            let infos = await manager.list()
            guard let info = infos.first(where: { $0.id.rawValue == pluginID }) else {
                box.send((false, "plugin not running"))
                return
            }
            box.send((info.state == .active, info.state == .active ? "active" : info.state.rawValue))
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let endpoint: WorkerEndpoint
    init(endpoint: WorkerEndpoint) {
        self.endpoint = endpoint
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: RemotePluginEndpoint.self)
        newConnection.exportedObject = endpoint
        newConnection.resume()
        return true
    }
}

@main
struct PluginWorkerMain {
    static func main() async {
        let endpoint = WorkerEndpoint()
        let delegate = ListenerDelegate(endpoint: endpoint)
        let listener = NSXPCListener(machServiceName: XPCPluginHost.serviceName)
        listener.delegate = delegate
        listener.resume()
        // 保持进程存活：永不 resume 的 continuation（挂起而非阻塞线程，XPC 回调照常调度）
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }
}
