import Foundation
@testable import HarnessApp

// MARK: - MCP 列表断言的唯一安全取项口径（D-16 真正根因的修复面，09-06）

//
// 机制（全部在本仓源码里，可核）：
//   ① `AppViewModel.registerStartupTools()` 会把内置内存演示服务器 `MockMCPClient(name: "local")`
//      注册进 mcpManager（AppViewModel.swift L589/L602）；
//   ② 它同时启动一个**后台发现 Task**（L606 起）去连 servers.json 里的服务器，
//      该 Task 结束时会再刷一次 mcpServers；
//   ③ `MCPServerManager.servers()` 是**按名排序**的（MCP.swift `descriptors.values.sorted`）。
// ⇒ "local" 出现在 mcpServers 里的时机 = 后台 Task 的进度，与本用例不确定；
//   于是 `mcpServers[0]` / `.first` 在名字排在 "local" **之后**的用例（rm-test / regtest /
//   theme-mcp / dsh-crew-*）里随时可能取到 "local"＝**选错卸载/重启对象**，
//   而 `count == 1` / `isEmpty` 在 "local" 出现后必然翻车。
//
// 这正是 D-16 两条「卸载后工具仍在列表」失败的真正根因：同一断言在 5.098s 撞上限、
// 把上限对齐到 20s 后又在 20.215s 失败——「等多久都不会消失」是选错对象的典型签名，
// 而我方当时先怀疑的是子进程回收延迟（该误判与纠正过程入册 QUALITY_REPORT 09-06 补记㉕）。
//
// ⇒ 下列两个访问器是这些用例的唯一安全口径：计数/存在性走 `userMCPServers`，
//   选卸载或重启对象一律走 `userMCPServer(named:)`，不得按下标。

extension AppViewModel {
    /// 内置内存演示服务器名（与 `AppViewModel.registerStartupTools()` 里的注册名一致）
    static let builtinDemoMCPServerName = "local"

    /// 仅用户导入/配置的 MCP 展示项（排除内置演示服务器）
    var userMCPServers: [MCPDisplayItem] {
        mcpServers.filter { $0.name != Self.builtinDemoMCPServerName }
    }

    /// 按名取用户 MCP 展示项（卸载/重启的对象一律按名选）
    func userMCPServer(named name: String) -> MCPDisplayItem? {
        mcpServers.first { $0.name == name }
    }
}
