import Foundation
import os.log
@testable import PluginXPC
@testable import ServiceContainer
import Testing

// MARK: - 测试替身

private final class FakeEndpoint: NSObject, RemotePluginEndpoint, @unchecked Sendable {
    var startReply: (Bool, String) = (true, "ok")
    var healthReply: (Bool, String?) = (true, "active")
    var calls: [String] = []
    private let lock = NSLock()

    private func record(_ name: String) {
        lock.withLock { calls.append(name) }
    }

    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func start(pluginID _: String, reply: @escaping (Bool, String) -> Void) {
        record("start")
        reply(startReply.0, startReply.1)
    }

    func stop(pluginID _: String, reply: @escaping (Bool, String) -> Void) {
        record("stop")
        reply(true, "ok")
    }

    func status(reply: @escaping ([String: String]) -> Void) {
        reply(["terminal": "active"])
    }

    func healthCheck(pluginID _: String, reply: @escaping (Bool, String?) -> Void) {
        record("healthCheck")
        reply(healthReply.0, healthReply.1)
    }
}

private final class FakeRunner: CommandRunner, @unchecked Sendable {
    let results: [(args: [String], exitCode: Int32, output: String)]
    var calls: [[String]] = []

    init(results: [(args: [String], exitCode: Int32, output: String)]) {
        self.results = results
    }

    /// 按前 3 个参数匹配（launchctl bootstrap 的 plist 路径是动态生成的）
    func run(_ args: [String]) throws -> (exitCode: Int32, output: String) {
        calls.append(args)
        for r in results where Array(r.args.prefix(3)) == Array(args.prefix(3)) {
            return (r.exitCode, r.output)
        }
        return (1, "")
    }
}

private func makeManifest(_ id: String = "com.harness.xpc.test") -> PluginManifest {
    PluginManifest(
        id: PluginID(id),
        name: "XPC Test",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "test",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
    )
}

// MARK: - Proxy 测试

@Suite("XPCPluginProxy Tests")
struct XPCPluginProxyTests {
    @Test("Start success activates proxy")
    func startSuccess() async throws {
        let endpoint = FakeEndpoint()
        let proxy = XPCPluginProxy(manifest: makeManifest(), endpoint: endpoint)
        try await proxy.start(context: .testContext())
        #expect(proxy.isActive)
    }

    @Test("Start failure throws with remote reason")
    func startFailure() async throws {
        let endpoint = FakeEndpoint()
        endpoint.startReply = (false, "boom")
        let proxy = XPCPluginProxy(manifest: makeManifest(), endpoint: endpoint)
        do {
            try await proxy.start(context: .testContext())
            Issue.record("Expected start failure")
        } catch let error as PluginXPCError {
            guard case let .remoteStartFailed(id, reason) = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
            #expect(id == "com.harness.xpc.test")
            #expect(reason == "boom")
        }
        #expect(proxy.isActive == false)
    }

    @Test("Stop deactivates proxy")
    func stop() async throws {
        let endpoint = FakeEndpoint()
        let proxy = XPCPluginProxy(manifest: makeManifest(), endpoint: endpoint)
        try await proxy.start(context: .testContext())
        await proxy.stop(context: .testContext())
        #expect(proxy.isActive == false)
    }

    @Test("Health check maps reply to PluginHealth")
    func healthCheck() async {
        let endpoint = FakeEndpoint()
        let proxy = XPCPluginProxy(manifest: makeManifest(), endpoint: endpoint)
        let healthy = await proxy.healthCheck()
        #expect(healthy.status == .healthy)

        endpoint.healthReply = (false, "stopped")
        let unhealthy = await proxy.healthCheck()
        #expect(unhealthy.status == .unhealthy)
        #expect(unhealthy.message == "stopped")
    }
}

// MARK: - Host 注册逻辑测试

@Suite("XPCPluginHost Tests")
struct XPCPluginHostTests {
    @Test("Skip submit when service already registered")
    func alreadyRegistered() async {
        let uid = getuid()
        let runner = FakeRunner(results: [
            (args: ["/bin/launchctl", "print", "gui/\(uid)/com.harness.pluginworker"], exitCode: 0, output: "exists"),
        ])
        let host = XPCPluginHost(runner: runner)
        #expect(await host.ensureWorkerRegistered(workerPath: "/bin/true"))
        #expect(runner.calls.count == 1)
    }

    @Test("Submit when service missing")
    func submitWhenMissing() async {
        let uid = getuid()
        let runner = FakeRunner(results: [
            (args: ["/bin/launchctl", "print", "gui/\(uid)/com.harness.pluginworker"], exitCode: 113, output: ""),
            (args: ["/bin/launchctl", "bootstrap", "gui/\(uid)", "/tmp/placeholder.plist"], exitCode: 0, output: ""),
        ])
        let host = XPCPluginHost(runner: runner)
        let ok = await host.ensureWorkerRegistered(workerPath: "/tmp/worker")
        #expect(ok)
        #expect(runner.calls.count == 2)
        #expect(runner.calls[1][0 ... 2] == ["/bin/launchctl", "bootstrap", "gui/\(uid)"])
    }

    @Test("Submit failure returns false")
    func submitFailure() async {
        let uid = getuid()
        let runner = FakeRunner(results: [
            (args: ["/bin/launchctl", "print", "gui/\(uid)/com.harness.pluginworker"], exitCode: 113, output: ""),
            (args: ["/bin/launchctl", "bootstrap", "gui/\(uid)", "/tmp/placeholder.plist"], exitCode: 5, output: "denied"),
        ])
        let host = XPCPluginHost(runner: runner)
        #expect(await host.ensureWorkerRegistered(workerPath: "/tmp/worker") == false)
        _ = uid
    }
}

// MARK: - 注销残留进程清理（P1：进程泄漏）

@Suite("XPCPluginHost deregister 残留清理")
struct XPCPluginHostCleanupTests {
    /// 线程安全的终止调用记录
    private final class PIDBox: @unchecked Sendable {
        private let lock = NSLock()
        private var pids: [Int32] = []
        func call(_ pid: Int32) {
            lock.withLock { pids.append(pid) }
        }

        var all: [Int32] {
            lock.withLock { pids }
        }
    }

    @Test("注销时对 bootout 后残留的 worker 发送终止信号")
    func deregisterTerminatesLeftovers() async {
        let uid = getuid()
        let runner = FakeRunner(results: [
            (args: ["/bin/launchctl", "bootstrap", "gui/\(uid)"], exitCode: 0, output: ""),
            (args: ["/usr/bin/pgrep", "-f", "/tmp/worker"], exitCode: 0, output: "123\n456"),
        ])
        let box = PIDBox()
        let host = XPCPluginHost(runner: runner, terminate: { pid in box.call(pid) })
        #expect(await host.ensureWorkerRegistered(workerPath: "/tmp/worker"))
        await host.deregister()
        #expect(box.all.sorted() == [123, 456])
    }

    @Test("未注册时注销不触发 pgrep")
    func deregisterWithoutRegistration() async {
        let runner = FakeRunner(results: [])
        let host = XPCPluginHost(runner: runner)
        await host.deregister()
        #expect(runner.calls.allSatisfy { $0.first != "/usr/bin/pgrep" })
    }

    @Test("注销幂等：二次注销不再清理")
    func deregisterIdempotent() async {
        let uid = getuid()
        let runner = FakeRunner(results: [
            (args: ["/bin/launchctl", "bootstrap", "gui/\(uid)"], exitCode: 0, output: ""),
            (args: ["/usr/bin/pgrep", "-f", "/tmp/worker"], exitCode: 0, output: ""),
        ])
        let box = PIDBox()
        let host = XPCPluginHost(runner: runner, terminate: { _ in box.call(1) })
        #expect(await host.ensureWorkerRegistered(workerPath: "/tmp/worker"))
        await host.deregister()
        await host.deregister()
        let pgrepCalls = runner.calls.filter { $0.first == "/usr/bin/pgrep" }.count
        #expect(pgrepCalls == 1)
        #expect(box.all.isEmpty)
    }
}

// MARK: - 端到端（真实 launchd + worker 进程，环境不支持时自动跳过）

@Suite("XPC E2E Tests")
struct XPCEndToEndTests {
    /// 仓库根目录下的 debug worker 二进制（swift test 运行时 .build 已构建）
    static var workerPath: String? {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 8 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent(".build/arm64-apple-macosx/debug/HarnessPluginWorker")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    static var e2eEnabled: Bool {
        workerPath != nil
    }

    @Test("Worker process serves plugins over real XPC", .enabled(if: Self.e2eEnabled))
    func e2e() async throws {
        let workerPath = try #require(Self.workerPath)
        let host = XPCPluginHost()

        // 清理残留注册（含历史崩溃/中断遗留）
        let uid = getuid()
        _ = try? ProcessCommandRunner().run(["launchctl", "bootout", "gui/\(uid)/\(XPCPluginHost.serviceName)"])

        do {
            try await e2eBody(workerPath: workerPath, host: host)
        } catch {
            // 任意失败路径都同步注销（含 bootout 后残留进程的 SIGTERM 清理），杜绝进程泄漏
            await host.deregister()
            throw error
        }
    }

    /// e2e 主体：注册 → 连接 → 跨进程插件启动/健康/停止 → 注销并断言进程退出
    private func e2eBody(workerPath: String, host: XPCPluginHost) async throws {
        #expect(await host.ensureWorkerRegistered(workerPath: workerPath))
        #expect(await host.connect())

        // 首次 ping 触发 launchd 拉起 worker，给足时间
        var alive = false
        for _ in 0 ..< 20 {
            alive = await host.isAlive(timeout: 3)
            if alive {
                break
            }
            try await Task.sleep(for: .seconds(0.5))
        }
        #expect(alive, "worker did not respond to ping")

        let manifest = PluginManifest(
            id: PluginID("terminal"), name: "终端",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "e2e",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
        )
        guard let proxy = await host.makeProxy(manifest: manifest) else {
            throw PluginXPCError.connectionLost
        }

        // 真实跨进程：worker 内安装 terminal 插件
        try await proxy.start(context: .testContext())
        #expect(proxy.isActive)

        let status = await proxy.remoteStatus()
        #expect(status["terminal"] == "active")

        let health = await proxy.healthCheck()
        #expect(health.status == .healthy)

        await proxy.stop(context: .testContext())
        #expect(proxy.isActive == false)

        await host.deregister()
        // 注销后 worker 应退出
        try await Task.sleep(for: .seconds(1))
        let check = try? ProcessCommandRunner().run(["/usr/bin/pgrep", "-f", "HarnessPluginWorker"])
        #expect(check?.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
                "worker process still running after deregister: \(check?.output ?? "?")")
    }
}

// MARK: - 辅助

private extension PluginContext {
    static func testContext() -> PluginContext {
        PluginContext(
            container: ServiceContainer(),
            eventBus: EventBus(),
            configuration: PluginConfiguration(),
            logger: Logger(subsystem: "test", category: "xpc"),
            cancellation: Cancellation()
        )
    }
}
