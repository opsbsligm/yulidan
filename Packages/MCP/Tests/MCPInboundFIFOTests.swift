import Foundation
@testable import MCP
import Testing

// MARK: - D-25(a2) 入站单条 FIFO 判别器（响应投递 vs 退出清理的竞速）

//
// 缺陷原貌（总账 D-25 H1，机制精确到行）：子进程「完全合法应答后毫秒级退出」时，
// `handleProcessExit` 那条裸 Task 可能先于响应行的裸 Task 被 actor 执行 ⇒
// `failAllPending(transportClosed)` 清空 pending ⇒ 随后到手的合法应答被 `resumePending`
// 静默丢弃 ⇒ 调用方看到 `transportClosed`。
//
// 判据设计（零墙钟）：不靠真实毫秒竞速，而是用**实例级**行处理闸门把「行已在消费者手里、
// 尚未结算」这个窗口钉开，再向同一条 FIFO 注入 `.processExited` ⇒ 竞速窗口 100% 命中。
// ⚠️ 测试缝刻意实例级（D-24 教训：静态缝会重演跨 suite 互清挂死）。

/// 一次性闸门：带标记的行进入时挂起，直到测试放行
///
/// ⚠️ Swift 6 禁止在 async 上下文直接 `lock()/unlock()` ⇒ 临界区一律放同步私有方法。
private final class OneShotGate: @unchecked Sendable {
    private let marker: String
    private let lock = NSLock()
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(marker: String) {
        self.marker = marker
    }

    /// 交给客户端的闸门闭包：只有含标记的行才被钉住
    func gate() -> @Sendable (String) async -> Void {
        { [weak self] line in
            guard let self, line.contains(marker) else { return }
            markEntered()
            await waitReleased()
        }
    }

    /// 等闸门被命中（== 目标行已出队、尚未结算）
    func waitEntered() async {
        if flagEntered() {
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            addEntryWaiter(cont)
        }
    }

    func release() {
        var pending: [CheckedContinuation<Void, Never>] = []
        lock.lock()
        released = true
        pending = releaseWaiters
        releaseWaiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    private func flagEntered() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entered
    }

    var isEntered: Bool {
        flagEntered()
    }

    private func markEntered() {
        var pending: [CheckedContinuation<Void, Never>] = []
        lock.lock()
        entered = true
        pending = entryWaiters
        entryWaiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    private func addEntryWaiter(_ cont: CheckedContinuation<Void, Never>) {
        lock.lock()
        if entered {
            lock.unlock()
            cont.resume()
        } else {
            entryWaiters.append(cont)
            lock.unlock()
        }
    }

    private func flagReleased() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return released
    }

    private func waitReleased() async {
        if flagReleased() {
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            addReleaseWaiter(cont)
        }
    }

    private func addReleaseWaiter(_ cont: CheckedContinuation<Void, Never>) {
        lock.lock()
        if released {
            lock.unlock()
            cont.resume()
        } else {
            releaseWaiters.append(cont)
            lock.unlock()
        }
    }
}

/// 应答 initialize / tools/list 后**保持存活**的服务器：
/// 让「进程退出」这件事完全由测试注入，而不是靠真实毫秒竞速。
private let liveServerSource = #"""
import json, sys, time


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


while True:
    raw = sys.stdin.readline()
    if not raw:
        break
    try:
        msg = json.loads(raw)
    except Exception:
        continue
    method = msg.get("method")
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": msg["id"], "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {"listChanged": True}},
            "serverInfo": {"name": "fifo-live", "version": "1"},
        }})
    elif method == "notifications/initialized":
        pass
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": msg["id"], "result": {"tools": [
            {"name": "fifo_probe_tool", "description": "d", "inputSchema": {"type": "object"}},
        ]}})
    # 其余方法一律不回话；进程不退出（退出由测试注入）
time.sleep(1)
"""#

/// 应答 initialize 后**立刻退出**且不回应 tools/list 的服务器
private let silentExitServerSource = #"""
import json, sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


while True:
    raw = sys.stdin.readline()
    if not raw:
        break
    try:
        msg = json.loads(raw)
    except Exception:
        continue
    if msg.get("method") == "initialize":
        send({"jsonrpc": "2.0", "id": msg["id"], "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "fifo-silent-exit", "version": "1"},
        }})
        sys.stdout.flush()
        # tools/list 不回话，直接退出：读端随后 EOF ⇒ 挂起请求必须被清理，不得永久挂起
        sys.exit(0)
"""#

private func writeScript(_ source: String, tag: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harness-fifo-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("server.py").path
    try source.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

private func makeClient(scriptPath: String, requestTimeout: TimeInterval) -> StdioMCPClient {
    StdioMCPClient(name: "fifo", configuration: StdioMCPConfiguration(
        command: "/usr/bin/env",
        arguments: ["python3", scriptPath],
        requestTimeout: requestTimeout,
        startupTimeout: 10
    ))
}

@Suite("MCP 入站 FIFO（D-25(a2)）")
struct MCPInboundFIFOTests {
    /// 核心判别器：响应行**已在结算途中**（闸门钉住）时，走生产投递点送进一枚终止通知
    /// ⇒ 调用方仍必须拿到那份合法应答。
    ///
    /// **本用例证明什么**：终止通知与响应结算只要共用同一条 FIFO，先到先结算，响应不被吞；
    /// 谁把 `noteProcessTerminated()` 改回「另起 Task 直接清理」（＝D-25 原架构形状），本用例转红
    /// （09-07 变异实测：改回后 `listTools()` 抛 `transportClosed`，与总账三次真实命中同型）。
    /// **不证明什么**：真实进程死亡与读线程的相对到达顺序（那由「EOF 必排在读线程所见数据行之后」
    /// 的因果性保证，并由 `exitStillFailsPendingAfterEOF` 用真死子进程覆盖另一半）。
    /// ⚠️ 曾经走过弯路：只把「消费者内部的立即结算」当变异体时本用例不会转红——FIFO 已把两者串行化，
    ///    变异必须打在**投递侧**（独立 hop）才等价于旧架构。这条弯路本身写在这里，防后人重犯。
    @Test("terminatingDuringSettlementDoesNotSwallowResponse")
    func terminatingDuringSettlementDoesNotSwallowResponse() async throws {
        let script = try writeScript(liveServerSource, tag: "live")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script, requestTimeout: 60)
        let gate = OneShotGate(marker: "fifo_probe_tool")
        await client.setLineGateForTesting(gate.gate())

        // 先发起请求：闸门会在「tools/list 响应行已出队、尚未结算」处把它钉住
        async let toolsTask: [MCPToolSpec] = client.listTools()
        await gate.waitEntered()
        // 竞速窗口钉开：此刻走**生产投递点**送一枚终止通知（它排在被钉住的行之后）
        client.noteProcessTerminated()
        #expect(gate.isEntered, "闸门未命中＝本用例没有真正钉住结算窗口，结论无效")
        gate.release()

        let tools = try await toolsTask
        #expect(tools.map(\.name) == ["fifo_probe_tool"],
                "已到手的合法应答被退出清理吃掉＝D-25 原缺陷复现")
        await client.stop()
    }

    /// 反面：读端 EOF 之后的终止事件仍须清理挂起请求（不得因为「延迟结算」而永久挂起）
    @Test("EOF 后的终止事件仍结算：挂起请求以 transportClosed 失败而非永久挂起")
    func exitStillFailsPendingAfterEOF() async throws {
        let script = try writeScript(silentExitServerSource, tag: "silent")
        defer { try? FileManager.default.removeItem(atPath: script) }
        // requestTimeout 远大于子进程死亡时间 ⇒ 观察到的一定是 transportClosed 而非超时
        let client = makeClient(scriptPath: script, requestTimeout: 60)
        do {
            _ = try await client.listTools()
            Issue.record("子进程已退出且不回应，listTools 不应成功")
        } catch let error as MCPError {
            guard case .transportClosed = error else {
                Issue.record("应为 transportClosed，实际 \(error)")
                return
            }
        }
        await client.stop()
    }

    /// 纯逻辑：FIFO 顺序与「关闭后先取空再终止」
    @Test("FIFO：入队顺序即出队顺序；close 后先把剩余事件取空再终止")
    func mailboxPreservesOrderAndDrains() async {
        let box = InboundMailbox()
        box.append(.line("a"))
        box.append(.line("b"))
        box.append(.readerEnded)
        box.close()
        var got: [String] = []
        while let event = await box.next() {
            switch event {
            case let .line(line): got.append(line)
            case .readerEnded: got.append("eof")
            case .processExited: got.append("exit")
            }
        }
        #expect(got == ["a", "b", "eof"])
        #expect(box.isClosed)
        // 关闭后 append 必须是丢弃而非崩溃/复活
        box.append(.line("dropped"))
        #expect(await box.next() == nil)
    }
}
