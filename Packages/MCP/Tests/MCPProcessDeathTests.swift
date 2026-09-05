import Foundation
import MCP
import Testing
import Tools

// MARK: - 子进程终止通知通道（Process.terminationHandler）判别器

//
// 存在理由（D-16 附带项，09-06）：原实现 `Task.detached { process.waitUntilExit() }` 把
// **同步阻塞**调用跑在 Swift 协作线程池上（官方对 waitUntilExit 的原文：
// 「Blocks the process until the receiver is finished.」），每个在册 stdio 客户端长期占死
// 一条协作线程直到子进程退出 ⇒ CI 高负载时协作池饥饿（全量门禁 flake 家族的放大器）。
// 改用官方 `terminationHandler` 后，「通知到底有没有送达」成了新的风险面，
// 故必须有「未送达就会变红」的用例，不能只做静态改法。

/// 通用最小 NDJSON JSON-RPC 服务器骨架（initialize / notifications/initialized / tools/list）
private let serverSkeleton = #"""
import json, os, sys

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def serve(tools, exit_after_tools):
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        mid = req.get("id")
        method = req.get("method")
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": mid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "death-probe-mcp", "version": "1.0.0"}}})
        elif method == "notifications/initialized":
            pass  # 通知无 id，不应答
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}})
            if exit_after_tools:
                return
        elif mid is not None:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "n/a"}})

"""#

/// A：首次运行正常应答后**自行退出**；二次启动立即退出（不握手）。
/// 「二次启动必失败」是判别器关键：死亡通知没送达 actor 时 `started`/`toolsCache` 仍是陈旧值，
/// `listTools()` 会直接吐缓存 ⇒ 幽灵在线（进程已死仍报可用）。
private let dyingServerSource = serverSkeleton + #"""
def main():
    marker = sys.argv[1]
    if os.path.exists(marker):
        return
    open(marker, "w").write("1")
    serve([{"name": "ghost", "description": "dies with the process",
            "inputSchema": {"type": "object"}}], exit_after_tools=True)

main()
"""#

/// B：应答后常驻，但 SIGTERM 后**故意再活 2 秒**（模拟子进程回收慢）。
/// 用于钉住「卸载路径不等子进程死亡」；同时把 pid 落盘供测试观察生死。
private let slowToDieServerSource = serverSkeleton + #"""
import signal
import time


def main():
    pid_path = sys.argv[1]
    open(pid_path, "w").write(str(os.getpid()))

    def on_term(signum, frame):
        time.sleep(2)  # 收到 SIGTERM 后再活 2s：任何「等子进程死亡」的实现都会被拖住
        os._exit(0)

    signal.signal(signal.SIGTERM, on_term)
    serve([{"name": "slow", "description": "ignores prompt death",
            "inputSchema": {"type": "object"}}], exit_after_tools=False)

main()
"""#

private func writeScript(_ source: String, _ filename: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("harness-mcp-death-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent(filename).path
    try source.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

private func alive(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0
}

// MARK: - 用例 A：终止通知必须送达（幽灵在线判别）

@Test("子进程自行退出后不得再吐缓存工具（terminationHandler 送达判别）")
func processDeathInvalidatesToolsCache() async throws {
    let script = try writeScript(dyingServerSource, "dying_server.py")
    defer { try? FileManager.default.removeItem(atPath: script) }
    let marker = script + ".first-run"
    defer { try? FileManager.default.removeItem(atPath: marker) }
    let client = StdioMCPClient(name: "dying", configuration: StdioMCPConfiguration(
        command: "/usr/bin/env",
        arguments: ["python3", script, marker],
        requestTimeout: 5,
        // 二次启动立即退出 → 握手以 startupTimeout 失败；取短值保持用例快
        startupTimeout: 2
    ))

    // ① 首次：握手成功 + 工具在册
    let specs = try await client.listTools()
    let firstNames = specs.map(\.name)
    #expect(firstNames == ["ghost"])

    // ② 等子进程自行死亡（脚本应答 tools/list 后即 return）
    try await Task.sleep(for: .milliseconds(600))

    // ③ 判别：通知送达 → started=false/toolsCache=nil → 重新 start() → 二次启动立即退出 → 抛错；
    //    通知未送达 → 直接返回缓存 ["ghost"]，即幽灵在线。
    do {
        let again = try await client.listTools()
        let cachedNames = again.map(\.name)
        Issue.record("幽灵在线：进程已死仍返回缓存工具 \(cachedNames)（终止通知未送达？）")
    } catch {
        #expect(error is MCPError, "期望 MCPError，实得 \(type(of: error))")
    }
}

// MARK: - 用例 B：卸载路径不等子进程死亡（D-16(a) 顺序钉）

@Test("disconnect 即时清注册表，不被慢死子进程拖住，且终止确被发起")
func disconnectDoesNotWaitForChildDeath() async throws {
    let script = try writeScript(slowToDieServerSource, "slowdie_server.py")
    defer { try? FileManager.default.removeItem(atPath: script) }
    let pidPath = script + ".pid"
    defer { try? FileManager.default.removeItem(atPath: pidPath) }

    let registry = ToolRegistry()
    let manager = MCPServerManager()
    let config = MCPServerConfig(name: "slowdie", command: "/usr/bin/env",
                                 arguments: ["python3", script, pidPath])
    let descriptor = await manager.connectStdio(config, into: registry)
    #expect(descriptor.isAvailable, "前置未成立：慢死服务器握手失败（\(descriptor.serverInfo ?? "nil")）")
    let names = await registry.names()
    #expect(names.contains("mcp_slowdie_slow"), "前置未成立：工具未注册（实得 \(names)）")
    let pidText = ((try? String(contentsOfFile: pidPath, encoding: .utf8)) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard pidText.isEmpty == false, let pidValue = Int(pidText) else {
        Issue.record("前置未成立：未读到子进程 pid（\(pidPath) 内容=\(pidText.prefix(16))）")
        return
    }
    let pid = pid_t(pidValue)

    let started = ContinuousClock.now
    await manager.disconnect(name: "slowdie", into: registry)
    let elapsed = started.duration(to: ContinuousClock.now)

    // ① 即时性：返回时注册表已无该服务器工具（不依赖子进程是否已死）
    let leftovers = await registry.names().filter { $0.hasPrefix("mcp_slowdie_") }
    #expect(leftovers.isEmpty, "卸载后残留工具：\(leftovers)")
    // ② 不等待死亡：子进程此刻仍可存活（SIGTERM 后 2s 才退），故 disconnect 必须早已返回
    #expect(elapsed < .seconds(1), "disconnect 耗时 \(elapsed)，疑似在等子进程死亡")
    // ③ 但 terminate 必须确实被发起：子进程最终要在 5s 内消失（否则 = 真孤儿进程）
    var gone = false
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if !alive(pid) {
            gone = true
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(gone, "子进程 \(pid) 未在 5s 内消失：terminate 未发起或被子进程长期忽略")
    #expect(await manager.isConnected(name: "slowdie") == false)
}
