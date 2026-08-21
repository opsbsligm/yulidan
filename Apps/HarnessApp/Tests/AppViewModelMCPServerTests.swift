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
        #expect(vm.mcpServers.count == 1)
        #expect(vm.mcpServers.first?.isAvailable == false)
        #expect(vm.mcpServers.first?.id == configs.first?.id)
        #expect(vm.showMCPImportForm == false)
    }

    // MARK: 用例 2：同名导入 = 更新（1 条、id 不变）

    @Test("同名导入 = 更新：条目唯一且 id 不变")
    func importSameNameUpdates() async {
        let (vm, mcpURL) = makeVM()

        await vm.importMCPServer(name: "dup", command: "/usr/bin/true",
                                 arguments: "", environment: "")
        guard let firstId = vm.mcpServers.first?.id else {
            Issue.record("首次导入后 mcpServers 为空")
            return
        }

        await vm.importMCPServer(name: "dup", command: "/usr/bin/false",
                                 arguments: "--x", environment: "")

        let configs = MCPDiscovery.loadConfigs(url: mcpURL)
        #expect(configs.count == 1)
        #expect(vm.mcpServers.count == 1)
        #expect(vm.mcpServers.first?.id == firstId)
        #expect(configs.first?.command == "/usr/bin/false")
        #expect(configs.first?.arguments == ["--x"])
    }

    // MARK: 用例 3：坏命令 → isAvailable=false + toolsLoadWarning

    @Test("坏命令：isAvailable=false 且 toolsLoadWarning 非空")
    func badCommandUnavailable() async {
        let (vm, _) = makeVM()

        await vm.importMCPServer(name: "broken", command: "/usr/bin/nonexistent_mcp_xyz_123",
                                 arguments: "", environment: "")

        #expect(vm.mcpServers.count == 1)
        #expect(vm.mcpServers.first?.isAvailable == false)
        #expect(vm.mcpServers.first?.toolCount == nil)
        #expect(vm.toolsLoadWarning?.contains("broken") == true)
    }

    // MARK: 用例 4：卸载 → 配置移除 + 断开

    @Test("卸载 MCP：servers.json 清空且服务器断开")
    func removeClearsConfig() async {
        let (vm, mcpURL) = makeVM()

        await vm.importMCPServer(name: "rm-test", command: "/usr/bin/true",
                                 arguments: "", environment: "")
        #expect(MCPDiscovery.loadConfigs(url: mcpURL).count == 1)

        let item = vm.mcpServers[0]
        await vm.removeMCPServer(item)

        #expect(MCPDiscovery.loadConfigs(url: mcpURL).isEmpty)
        #expect(vm.mcpServers.isEmpty)
        #expect(await vm.mcpManager.isConnected(name: "rm-test") == false)
    }

    // MARK: 用例 5：重启故障服务器 → 快速失败、配置保留

    @Test("重启坏服务器：快速失败且配置保留")
    func retryBrokenServerKeepsConfig() async {
        let (vm, mcpURL) = makeVM()

        await vm.importMCPServer(name: "broken2", command: "/usr/bin/nonexistent_mcp_xyz_123",
                                 arguments: "", environment: "")

        let item = vm.mcpServers[0]
        await vm.retryMCPServer(item)

        #expect(vm.mcpServers.count == 1)
        #expect(vm.mcpServers.first?.isAvailable == false)
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
}
