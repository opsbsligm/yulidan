import Foundation
@testable import HarnessApp
import MCP
import Testing

// MARK: - 卸载 × 启动期 MCP 连接竞态（QUALITY ㉙ 观察项 F-a 的根因锁死）

/// 竞态本体：`registerStartupTools` 先读 servers.json **快照**，再逐个 `await connectStdio`；
/// 若卸载落在「快照之后、该次连接完成之前」，被卸载的服务器会被重新登记（复活）——
/// 实测症状＝主题不回落系统基准 / 工具重新注册 / 列表条目复活（并行负载下窗口变宽，
/// 这正是 F-a 只在 `swift test --parallel` 稀发复现的原因）。
/// 判据＝纯结构化：双向信号门把窗口钉成确定时序，零墙钟、零 sleep、零前台、锁屏可跑。
@MainActor
@Suite("卸载 × 启动 MCP 连接竞态", .serialized)
struct MCPRemoveDuringStartupRaceTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    /// 一次性事件（actor 隔离）：测试侧与钩子侧各等一次，用于确定交错次序
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

    @Test("卸载落在启动连接窗口内 ⇒ 被卸载服务器不得复活（守卫判别器）")
    func removedServerMustNotResurrect() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-mcp-race-\(UUID().uuidString)")
        let configURL = dir.appendingPathComponent("servers.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 夹具取 /usr/bin/false（立即退出）：connectStdio 走 catch 分支，
        // 而该分支同样登记 descriptor（isAvailable=false）⇒ 判别面存在，
        // 且无需真子进程、无网络、无窗口（静默合规）。
        let victim = MCPServerConfig(name: "race-victim", command: "/usr/bin/false",
                                     arguments: [], environment: [:])
        // 哨兵＝循环里 victim 之后的下一项：顺序循环 ⇒ 「到达哨兵」即证明
        // victim 那一次连接与其后的守卫都已执行完（结构性完成判据，不用等待时间）
        let sentinel = MCPServerConfig(name: "race-sentinel", command: "/usr/bin/false",
                                       arguments: [], environment: [:])
        // 关键：配置在 VM init **之前**落盘 ⇒ 启动快照必含二者（否则窗口无从形成）
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

        let vm = AppViewModel(skillUserDirectory: dir.appendingPathComponent("skills"),
                              sessionDBURL: dir.appendingPathComponent("sessions.sqlite"),
                              mcpConfigURLOverride: configURL,
                              startupMCPConnectGate: gate)

        // ① 循环已停在「即将连接 victim」这一点上（窗口打开）
        let reachedVictim = await victimReached.waitForDone(timeout: .seconds(60))
        if reachedVictim == false {
            Issue.record("启动链 60s 内未到达 victim 连接点 ⇒ 挂死保险生效，改判失败而非拖死整轮门禁（历史根因＝静态测试缝跨 suite 争用，已修；见 QUALITY ㉜）")
            await releaseVictim.fire()
            await pastVictim.fire()
            return
        }

        // ② 在窗口内按 UI 同一路径卸载（同一函数、同一移除口径）
        let item = MCPDisplayItem(id: victim.id, name: victim.name, command: victim.command,
                                  arguments: victim.arguments, isAvailable: false,
                                  toolCount: nil, serverInfo: nil, isTheme: false)
        await vm.removeMCPServer(item)

        // ③ 放行连接：守卫② 应在此刻发现配置已消失并立即断开
        await releaseVictim.fire()
        // ④ 循环越过哨兵 ⇒ 守卫链已跑完（无需任何 sleep/轮询）
        let pastDone = await pastVictim.waitForDone(timeout: .seconds(60))
        if pastDone == false {
            Issue.record("放行后 60s 内启动链未越过哨兵 ⇒ 挂死保险生效，改判失败而非拖死整轮门禁（同上，QUALITY ㉜）")
            return
        }

        let descriptors = await vm.mcpManager.servers().map(\.name)
        let victimResurrected = descriptors.contains("race-victim")
        #expect(!victimResurrected, "被卸载服务器被启动连接复活（descriptor 仍在册）：\(descriptors)")
    }
}
