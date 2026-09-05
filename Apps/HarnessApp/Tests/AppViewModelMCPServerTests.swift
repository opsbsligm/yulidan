import Foundation
@testable import HarnessApp
import MCP
import ServiceContainer
import Testing

// MARK: - P0.4 MCP stdio 服务器：导入 / 同名更新 / 坏命令 / 重启 / 卸载 / 环境变量解析

//
// 隔离纪律：mcpConfigURLOverride 为实例级测试缝（经 init 注入），
// 每个用例独立临时 URL，防泄漏到真实 ~/.harness/mcp/servers.json。

@MainActor
@Suite("AppViewModel P0.4 MCP stdio 服务器", .serialized)
struct AppViewModelMCPServerTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    /// 每用例独立临时配置 URL（实例级注入，无共享状态）
    private func makeVM() -> (vm: AppViewModel, mcpConfigURL: URL) {
        let mcpConfigURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-mcp-test-\(UUID().uuidString)")
            .appendingPathComponent("servers.json")
        let vm = AppViewModel(
            skillUserDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-mcp-skills-\(UUID().uuidString)"),
            sessionDBURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-mcp-test-\(UUID().uuidString).sqlite"),
            mcpConfigURLOverride: mcpConfigURL
        )
        return (vm, mcpConfigURL)
    }

    // MARK: 用例 1：导入写入临时 servers.json（命令/参数/环境变量解析）

    @Test("导入 MCP：配置落盘（command/arguments/environment 解析）")
    func importWritesConfig() async {
        let (vm, mcpURL) = makeVM()

        await vm.importMCPServer(name: "fs-test", command: "/usr/bin/true",
                                 arguments: "-h --verbose", environment: "FOO=bar BAZ=qux")

        let configs = MCPDiscovery.loadConfigs(url: mcpURL)
        #expect(configs.count == 1)
        #expect(configs.first?.name == "fs-test")
        #expect(configs.first?.command == "/usr/bin/true")
        #expect(configs.first?.arguments == ["-h", "--verbose"])
        #expect(configs.first?.environment == ["FOO": "bar", "BAZ": "qux"])
        // /usr/bin/true 立即退出 → 连接不可用，但配置已落盘、列表已刷新
        #expect(vm.userMCPServers.count == 1)
        #expect(vm.userMCPServers.first?.isAvailable == false)
        #expect(vm.userMCPServers.first?.id == configs.first?.id)
        #expect(vm.showMCPImportForm == false)
    }

    // MARK: 用例 2：同名导入 = 更新（1 条、id 不变）

    @Test("同名导入 = 更新：条目唯一且 id 不变")
    func importSameNameUpdates() async {
        let (vm, mcpURL) = makeVM()

        await vm.importMCPServer(name: "dup", command: "/usr/bin/true",
                                 arguments: "", environment: "")
        guard let firstId = vm.userMCPServers.first?.id else {
            Issue.record("首次导入后 mcpServers 为空")
            return
        }

        await vm.importMCPServer(name: "dup", command: "/usr/bin/false",
                                 arguments: "--x", environment: "")

        let configs = MCPDiscovery.loadConfigs(url: mcpURL)
        #expect(configs.count == 1)
        #expect(vm.userMCPServers.count == 1)
        #expect(vm.userMCPServers.first?.id == firstId)
        #expect(configs.first?.command == "/usr/bin/false")
        #expect(configs.first?.arguments == ["--x"])
    }

    // MARK: 用例 3：坏命令 → isAvailable=false + toolsLoadWarning

    @Test("坏命令：isAvailable=false 且 toolsLoadWarning 非空")
    func badCommandUnavailable() async {
        let (vm, _) = makeVM()

        await vm.importMCPServer(name: "broken", command: "/usr/bin/nonexistent_mcp_xyz_123",
                                 arguments: "", environment: "")

        #expect(vm.userMCPServers.count == 1)
        #expect(vm.userMCPServers.first?.isAvailable == false)
        #expect(vm.userMCPServers.first?.toolCount == nil)
        #expect(vm.toolsLoadWarning?.contains("broken") == true)
    }

    // MARK: 用例 4：卸载 → 配置移除 + 断开

    @Test("卸载 MCP：servers.json 清空且服务器断开")
    func removeClearsConfig() async {
        let (vm, mcpURL) = makeVM()

        await vm.importMCPServer(name: "rm-test", command: "/usr/bin/true",
                                 arguments: "", environment: "")
        #expect(MCPDiscovery.loadConfigs(url: mcpURL).count == 1)

        // 选卸载对象按名取（见 MCPUserListFilter.swift 的口径说明）
        guard let item = vm.userMCPServer(named: "rm-test") else {
            Issue.record("前置未成立：列表里没有 rm-test（实得 \(vm.userMCPServers.map(\.name))）")
            return
        }
        await vm.removeMCPServer(item)

        #expect(MCPDiscovery.loadConfigs(url: mcpURL).isEmpty)
        #expect(vm.userMCPServers.isEmpty)
        #expect(await vm.mcpManager.isConnected(name: "rm-test") == false)
    }

    // MARK: 用例 5：重启故障服务器 → 快速失败、配置保留

    @Test("重启坏服务器：快速失败且配置保留")
    func retryBrokenServerKeepsConfig() async {
        let (vm, mcpURL) = makeVM()

        await vm.importMCPServer(name: "broken2", command: "/usr/bin/nonexistent_mcp_xyz_123",
                                 arguments: "", environment: "")

        // 选重启对象按名取
        guard let item = vm.userMCPServer(named: "broken2") else {
            Issue.record("前置未成立：列表里没有 broken2（实得 \(vm.userMCPServers.map(\.name))）")
            return
        }
        await vm.retryMCPServer(item)

        #expect(vm.userMCPServers.count == 1)
        #expect(vm.userMCPServers.first?.isAvailable == false)
        #expect(MCPDiscovery.loadConfigs(url: mcpURL).count == 1)
        #expect(await vm.mcpManager.isConnected(name: "broken2") == false)
    }

    // MARK: 用例 6：运行日志（无 stderr 输出 → 占位提示）

    @Test("mcpServerLog：无 stderr 输出时返回占位提示")
    func mcpServerLogPlaceholder() async {
        let (vm, _) = makeVM()
        let item = MCPDisplayItem(id: "log-none", name: "log-none", command: "/usr/bin/true",
                                  arguments: [], isAvailable: false, toolCount: nil, serverInfo: nil, isTheme: false)
        let log = await vm.mcpServerLog(item)
        #expect(log.contains("stderr"))
    }

    // MARK: 用例 7：parseEnvPairs 纯函数（合法 / 多对 / 非法丢弃 / 值含等号）

    @Test("parseEnvPairs：合法、多对、非法项丢弃、值含等号")
    func parseEnvPairsCases() {
        #expect(AppViewModel.parseEnvPairs("FOO=bar BAZ=qux") == ["FOO": "bar", "BAZ": "qux"])
        #expect(AppViewModel.parseEnvPairs("A=1") == ["A": "1"])
        #expect(AppViewModel.parseEnvPairs("NOEQUALS FOO=bar") == ["FOO": "bar"])
        #expect(AppViewModel.parseEnvPairs("=value OK=1") == ["OK": "1"])
        #expect(AppViewModel.parseEnvPairs("") == [:])
        #expect(AppViewModel.parseEnvPairs("A=B=C") == ["A": "B=C"])
    }

    // MARK: 用例 8：真实 stdio MCP 服务器 — 工具自动注册进工具页 / 卸载即时移除

    @Test("MCP 导入：工具自动注册进工具列表；卸载 → 工具即时移除 + 服务器断开")
    func importRegistersToolsRemoveDropsThem() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-mcp-regtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("regtest_server.py").path
        try minimalMCPServerSource.write(toFile: script, atomically: true, encoding: .utf8)

        let (vm, _) = makeVM()
        await vm.importMCPServer(name: "regtest", command: "/usr/bin/env",
                                 arguments: "python3 \(script)", environment: "")

        // 等待握手完成 + 工具注册进工具列表（工具页自动注册链路）
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if vm.userMCPServer(named: "regtest")?.isAvailable == true,
               vm.tools.contains(where: { $0.name == "mcp_regtest_echo" }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(vm.userMCPServer(named: "regtest")?.isAvailable == true)
        #expect(vm.tools.contains(where: { $0.name == "mcp_regtest_echo" }))

        // 卸载：工具**即时**移除 + 服务器断开。
        // ⚠️ 这里刻意**不留宽限循环**（原为 5s 轮询，2026-08-25 高负载瞬态失败后加的对称加固）：
        //   宽限把「卸载后工具迟迟不消失」的用户可感知缺陷折算成测试等待，正是 D-16 期间
        //   「上限 5s→20s 试探」被实测撤销的同一条理由（QUALITY_REPORT 09-06 补记㉕）。
        //   现在钉住的语义＝「removeMCPServer 返回时工具已下线」——removeMCPServer 内部
        //   以 await refreshTools() 收尾（AppViewModel.swift L1054 起），返回时快照已刷新完毕，无需轮询。
        //   ⇒ 本行若再次变红，含义是「即时性被破坏」或「协作线程池又饿了」，处置方向是查根因，
        //     不是把循环加回来。
        // 选卸载对象按名取——曾因按下标取到内置演示服务器 "local"（按名排序在前），
        // 导致「卸载了 regtest，regtest 工具当然还在」的假缺陷（D-16 真正根因）
        guard let victim = vm.userMCPServer(named: "regtest") else {
            Issue.record("前置未成立：列表里没有 regtest（实得 \(vm.userMCPServers.map(\.name))）")
            return
        }
        await vm.removeMCPServer(victim)
        #expect(!vm.tools.contains(where: { $0.name.hasPrefix("mcp_regtest_") }))
        #expect(await vm.mcpManager.isConnected(name: "regtest") == false)
    }
}

/// 最小 MCP 服务器（python3 stdio NDJSON；initialize/tools/list/tools/call，无外部日志写）
private let minimalMCPServerSource = #"""
import json, sys

def main():
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
        params = msg.get("params") or {}
        if method == "initialize":
            result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "regtest", "version": "0.0.1"}}
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n")
            sys.stdout.flush()
        elif method == "ping":
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": {}}) + "\n")
            sys.stdout.flush()
        elif method == "tools/list":
            tools = [{"name": "echo", "description": "echo text", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}}]
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}}) + "\n")
            sys.stdout.flush()
        elif method == "tools/call":
            text = str((params.get("arguments") or {}).get("text", ""))
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "echo: " + text}]}}) + "\n")
            sys.stdout.flush()

main()
"""#
