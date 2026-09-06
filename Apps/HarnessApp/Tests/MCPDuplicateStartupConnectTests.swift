import Foundation
@testable import HarnessApp
import MCP
import Testing

// MARK: - D-21：启动链对「已在用服务器」的重复连接（stdio 子进程泄漏 ＋ 卸载后短暂复活）

/// **缺陷本体（实测，非推测）**：`registerStartupTools()` 的 MCP 循环照配置**快照**逐个连接，
/// 完全不检查该名字此刻是否已被 `importMCPServer` / `retryMCPServer` 连上；而
/// `MCPManager.connectStdio` 里 `clients[config.name] = client` 是无条件覆盖 ⇒
/// ① 被覆盖的旧实例从此无人引用，它的 stdio 子进程**永远不会被终止**（＝「卸载了服务器，进程还在跑」）；
/// ② 新客户端迟到的工具注册／循环收尾的 `refreshThemes()` 会让「刚卸载的工具／主题」短暂复活
///   ——全量门禁稀发失败 `AppViewModelMCPServerTests:205` 与观察项 F-a 是同族机制（QUALITY ㉛）。
/// 判据＝**进程级副作用**（子进程自己写启动标记 + `ps` 实测存活），不看任何日志 token（教训：QUALITY ㉙）。
@MainActor
@Suite("启动连接幂等 × 卸载（D-21 子进程泄漏）", .serialized)
struct MCPDuplicateStartupConnectTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    /// 一次性事件（actor 隔离）：测试侧与钩子侧各等一次，用于确定交错次序（与 D-20 用例同法）
    private actor Signal {
        private var done = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if done {
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func fire() {
            guard !done else { return }
            done = true
            let pending = waiters
            waiters.removeAll()
            for continuation in pending {
                continuation.resume()
            }
        }

        /// 有界推进等待：true＝信号已到；false＝超时（调用方必须 Issue.record + fire() 放行钩子后 return）。
        /// ⚠️ 这是**挂死保险**，不是判据：判据仍是「信号到达」这一结构事实。并行态高载下后台启动 Task
        /// 任何原因（历史实测＝静态测试缝被并行 suite 清空钩子，D-24）都可能让它永不到达；无界等待会挂死整轮门禁，超时改判失败＝方向安全。
        func waitForDone(timeout: Duration, poll: Duration = .milliseconds(5)) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while !done {
                if ContinuousClock.now >= deadline {
                    return false
                }
                try? await Task.sleep(for: poll)
            }
            return true
        }
    }

    /// 建立一次性夹具：内嵌 stdio 服务器脚本 + 空的启动标记文件（子进程自行追加 ⇒ 行数＝启动次数）
    private func makeFixture(prefix: String) throws -> (dir: URL, markerURL: URL, scriptURL: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let markerURL = dir.appendingPathComponent("spawns.txt")
        try Data().write(to: markerURL)
        let scriptURL = dir.appendingPathComponent("d21_server.py")
        try dupConnectServerSource.write(to: scriptURL, atomically: true, encoding: .utf8)
        return (dir, markerURL, scriptURL)
    }

    @Test("导入已连过的服务器 ⇒ 启动链不得重复连接；卸载后不得残留其子进程")
    func startupMustNotDoubleConnectImportedServer() async throws {
        let fixture = try makeFixture(prefix: "harness-mcp-dupconnect")
        let markerURL = fixture.markerURL
        let scriptPath = fixture.scriptURL.path
        let markerPath = markerURL.path
        let configURL = fixture.dir.appendingPathComponent("servers.json")
        defer { try? FileManager.default.removeItem(at: fixture.dir) }

        // 配置在 VM init **之前**落盘 ⇒ 启动快照必含二者；sentinel 用于证明「循环已走完 victim」
        let victim = MCPServerConfig(name: "d21-victim", command: "/usr/bin/env",
                                     arguments: ["python3", scriptPath],
                                     environment: ["HARNESS_TEST_MARKER": markerPath])
        let sentinel = MCPServerConfig(name: "d21-sentinel", command: "/usr/bin/false",
                                       arguments: [], environment: [:])
        try MCPDiscovery.save([victim, sentinel], url: configURL)

        let victimReached = Signal()
        let releaseVictim = Signal()
        let pastVictim = Signal()
        let victimName = victim.name

        // ⚠️ 钩子经 **init 注入到实例**（而非静态全局）：并行态两个 suite 共用静态缝会互相清空对方钩子
        // ⇒ 永不到达（实测两套件单独并行各绿、同跑必红）。QUALITY ㉜ / 同族先例 P4。
        let gate: @Sendable (String) async -> Void = { name in
            if name == victimName {
                await victimReached.fire()
                await releaseVictim.wait()
            } else {
                await pastVictim.fire()
            }
        }

        let vm = AppViewModel(skillUserDirectory: fixture.dir.appendingPathComponent("skills"),
                              sessionDBURL: fixture.dir.appendingPathComponent("sessions.sqlite"),
                              mcpConfigURLOverride: configURL,
                              startupMCPConnectGate: gate)

        // ① 循环停在「即将连接 victim」上（守卫①②尚未执行）
        let reachedVictim = await victimReached.waitForDone(timeout: .seconds(60))
        if reachedVictim == false {
            Issue.record("启动链 60s 内未到达 victim 连接点 ⇒ 挂死保险生效，改判失败而非拖死整轮门禁（历史根因＝静态测试缝跨 suite 争用，已修；见 QUALITY ㉜）")
            await releaseVictim.fire()
            await pastVictim.fire()
            return
        }
        // ② 窗口内走 UI 同一路径导入同名服务器 ⇒ 导入自己完成第一次连接（可用态）
        await vm.importMCPServer(name: "d21-victim", command: "/usr/bin/env",
                                 arguments: "python3 \(scriptPath)",
                                 environment: "HARNESS_TEST_MARKER=\(markerPath)")
        // ③ 放行：有幂等守卫 ⇒ 循环看到「已可用」直接跳过；无守卫 ⇒ 再连一次（多一个子进程）
        await releaseVictim.fire()
        // ④ 循环越过哨兵 ⇒ victim 那一次的处理已定局（结构性完成判据，不靠等待时间）
        let pastDone = await pastVictim.waitForDone(timeout: .seconds(60))
        if pastDone == false {
            Issue.record("放行后 60s 内启动链未越过哨兵 ⇒ 挂死保险生效，改判失败而非拖死整轮门禁（同上，QUALITY ㉜）")
            return
        }

        let spawns = spawnCount(at: markerURL)
        #expect(spawns == 1, "启动链对已连过的服务器重复连接：子进程启动 \(spawns) 次（应为 1）")

        // ⑤ 卸载后不得残留该服务器的子进程（缺陷①的用户可见面：进程还在跑）
        guard let item = vm.userMCPServer(named: "d21-victim") else {
            Issue.record("前置未成立：列表里没有 d21-victim")
            return
        }
        await vm.removeMCPServer(item)
        // terminate → 进程消失是跨进程异步，这里「一旦干净立刻返回」，上限只是兜底而非判别阈值
        let survivors = await pollChildren(matching: scriptPath) { !$0.isEmpty }
        #expect(survivors.isEmpty, "卸载后仍残留 \(survivors.count) 个该服务器的子进程：\(survivors)")
    }

    // MARK: 缺陷①本体：同名重复连接必须先终止被覆盖的旧实例（绕过幂等守卫，直测 MCP 层加固）

    @Test("同名重复 connectStdio ⇒ 被覆盖的旧实例必须已终止（不留孤儿进程）")
    func repeatedConnectMustStopPreviousClient() async throws {
        let fixture = try makeFixture(prefix: "harness-mcp-orphan")
        let markerURL = fixture.markerURL
        let scriptPath = fixture.scriptURL.path
        let markerPath = markerURL.path
        defer { try? FileManager.default.removeItem(at: fixture.dir) }

        // 本用例**故意**绕过 AppViewModel 的幂等守卫，直接对 MCP 层连两次同名服务器：
        // 判据面＝`connectStdio` 内部「覆盖 clients[name] 之前先 stop 旧实例」这条加固本身
        let manager = MCPServerManager()
        let config = MCPServerConfig(name: "d21-dup", command: "/usr/bin/env",
                                     arguments: ["python3", scriptPath],
                                     environment: ["HARNESS_TEST_MARKER": markerPath])
        _ = await manager.connectStdio(config, into: nil)
        _ = await manager.connectStdio(config, into: nil)
        defer { Task { await manager.disconnect(name: "d21-dup") } }

        let spawns = spawnCount(at: markerURL)
        #expect(spawns == 2, "前置未成立：同名连接未真正发生两次（实得 \(spawns)）⇒ 本用例失去判别面")

        let survivors = await pollChildren(matching: scriptPath) { $0.count > 1 }
        #expect(survivors.count <= 1, "同名重复连接残留 \(survivors.count) 个存活子进程（被覆盖的旧实例未终止）：\(survivors)")
    }
}

/// 数一数子进程启动了几次（每行＝一个进程自己写的「我起来了」）
private func spawnCount(at url: URL) -> Int {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
    return text.split(separator: "\n").count
}

/// 轮询进程表直到谓词不再成立（或用完兜底轮次）。⚠️上限只是兜底，判据仍是返回值的实测观测。
private func pollChildren(matching marker: String, maxRounds: Int = 30,
                          while predicate: @Sendable ([Int32]) -> Bool) async -> [Int32] {
    var survivors = liveChildPIDs(matching: marker)
    var round = 0
    while predicate(survivors), round < maxRounds {
        try? await Task.sleep(for: .milliseconds(100))
        survivors = liveChildPIDs(matching: marker)
        round += 1
    }
    return survivors
}

/// 只读枚举当前测试进程的子进程里命令行含 marker 的 pid（判据＝进程表实测，非日志 token）
private func liveChildPIDs(matching marker: String) -> [Int32] {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-Ao", "pid=,ppid=,args="]
    let pipe = Pipe()
    ps.standardOutput = pipe
    guard (try? ps.run()) != nil else { return [] }
    // ⚠️ 顺序即正确性：全量 ps 输出远超管道缓冲（64KB），先 waitUntilExit 会与 ps 的写入互等成死锁
    // （本轮实测挂起 4 分钟）。必须先读到 EOF（进程退出时写端关闭），再收尸。
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    let myPID = ProcessInfo.processInfo.processIdentifier
    var alive: [Int32] = []
    for row in text.split(separator: "\n") {
        let cols = row.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard cols.count == 3, Int32(cols[1]) == myPID, cols[2].contains(marker) else { continue }
        if let pid = Int32(cols[0]) {
            alive.append(pid)
        }
    }
    return alive
}

/// 最小 MCP 服务器（python3 stdio NDJSON）：启动即向 HARNESS_TEST_MARKER 追加一行，
/// 使「被连接次数」在进程外可数；握手成功但保持存活（真实服务器形态）
private let dupConnectServerSource = #"""
import json, os, sys

marker = os.environ.get("HARNESS_TEST_MARKER")
if marker:
    with open(marker, "a") as handle:
        handle.write("up\n")
        handle.flush()

def reply(mid, result):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n")
    sys.stdout.flush()

while True:
    line = sys.stdin.readline()
    if not line:
        break
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except Exception:
        continue
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        reply(mid, {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}},
                    "serverInfo": {"name": "d21", "version": "0.0.1"}})
    elif method == "ping":
        reply(mid, {})
    elif method == "tools/list":
        reply(mid, {"tools": [{"name": "echo", "description": "echo text",
                               "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}}]})
    elif method == "tools/call":
        # 必须应答 tools/call：refreshThemes 会对在册服务器试调用，静默不回 ⇒ 请求等满 30s 超时
        #（本轮实测：缺此分支时该用例耗时 31.9s，正是 requestTimeout）
        args = (msg.get("params") or {}).get("arguments") or {}
        reply(mid, {"content": [{"type": "text", "text": "echo: " + str(args.get("text", ""))}]})

"""#
