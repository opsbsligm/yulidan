import Foundation
import ServiceContainer

/// 命令执行抽象：生产走 /bin/launchctl，测试注入假实现
public protocol CommandRunner: Sendable {
    func run(_ args: [String]) throws -> (exitCode: Int32, output: String)
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    /// 直接 exec，不经 shell（路径含空格不会被拆词）
    public func run(_ args: [String]) throws -> (exitCode: Int32, output: String) {
        guard !args.isEmpty else { throw PluginXPCError.connectionLost }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0].hasPrefix("/") ? args[0] : "/bin/\(args[0])")
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// XPC 插件宿主：把 worker 注册到 launchd 并维持连接。
/// worker 以 machServiceName 监听；主进程按名连接（launchd 按需拉起）。
public actor XPCPluginHost {
    public static let serviceName = "com.harness.pluginworker"

    public private(set) var isAvailable = false
    private var connection: NSXPCConnection?
    private var endpoint: (any RemotePluginEndpoint)?
    private let runner: any CommandRunner

    public init(runner: any CommandRunner = ProcessCommandRunner()) {
        self.runner = runner
    }

    /// 生成 worker 的 launchd plist（MachServices 声明是 machServiceName 可达的前提）
    static func plistContents(workerPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(serviceName)</string>
            <key>MachServices</key>
            <dict>
                <key>\(serviceName)</key>
                <true/>
            </dict>
            <key>ProgramArguments</key>
            <array>
                <string>\(workerPath)</string>
            </array>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    /// 把 worker 注册为用户会话 launchd 服务（幂等：已加载则跳过）。
    /// 用 plist + bootstrap 而非 submit：submit 不注册 MachServices，machServiceName 不可达。
    @discardableResult
    public func ensureWorkerRegistered(workerPath: String) -> Bool {
        let uid = getuid()
        let existsCheck: (exitCode: Int32, output: String)
        do {
            existsCheck = try runner.run(["/bin/launchctl", "print", "gui/\(uid)/\(Self.serviceName)"])
        } catch {
            existsCheck = (-1, "")
        }
        if existsCheck.exitCode == 0 {
            return true
        }
        guard let plistPath = Self.writePlist(workerPath: workerPath) else { return false }
        do {
            let result = try runner.run(["/bin/launchctl", "bootstrap", "gui/\(uid)", plistPath])
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    private static func writePlist(workerPath: String) -> String? {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Harness", isDirectory: true)
        guard let base else { return nil }
        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let url = base.appendingPathComponent("\(Self.serviceName).plist")
        do {
            try plistContents(workerPath: workerPath).write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            return nil
        }
    }

    /// 建立 XPC 连接（懒连接：首次远端调用时真正握手）；handler 负责断链标记
    @discardableResult
    public func connect() -> Bool {
        guard connection == nil else { return isAvailable }
        let conn = NSXPCConnection(machServiceName: Self.serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: RemotePluginEndpoint.self)
        conn.interruptionHandler = { [weak self] in
            Task { await self?.markDisconnected() }
        }
        conn.invalidationHandler = { [weak self] in
            Task { await self?.markDisconnected() }
        }
        conn.resume()
        connection = conn
        endpoint = conn.remoteObjectProxy as? any RemotePluginEndpoint
        isAvailable = endpoint != nil
        return isAvailable
    }

    /// ping 探活：worker 存活且响应为 true
    public func isAlive(timeout: TimeInterval = 3) async -> Bool {
        guard let endpoint else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            // deadline 与 reply 可能竞态，仅允许 resume 一次
            final class OnceBox: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                init(_ cont: CheckedContinuation<Bool, Never>) {
                    self.cont = cont
                }

                private let cont: CheckedContinuation<Bool, Never>
                func once(_ value: Bool) {
                    let allowed = lock.withLock {
                        guard !resumed else { return false }
                        resumed = true
                        return true
                    }
                    if allowed {
                        cont.resume(returning: value)
                    }
                }
            }
            let box = OnceBox(cont)
            let deadline = Task {
                try? await Task.sleep(for: .seconds(timeout))
                box.once(false)
            }
            endpoint.ping { alive in
                deadline.cancel()
                box.once(alive)
            }
        }
    }

    /// 创建指向 worker 的进程内 Plugin 代理（未连接时返回 nil）
    public func makeProxy(manifest: PluginManifest) -> XPCPluginProxy? {
        guard let endpoint else { return nil }
        return XPCPluginProxy(manifest: manifest, endpoint: endpoint)
    }

    public func disconnect() {
        connection?.invalidate()
        connection = nil
        endpoint = nil
        isAvailable = false
    }

    /// 从 launchd 注销 worker（bootout 会同时结束 worker 进程）
    public func deregister() {
        let uid = getuid()
        try? runner.run(["/bin/launchctl", "bootout", "gui/\(uid)/\(Self.serviceName)"])
        disconnect()
    }

    private func markDisconnected() {
        connection = nil
        endpoint = nil
        isAvailable = false
    }
}
