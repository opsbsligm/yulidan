import Foundation
@testable import HarnessApp
import MCP
import Testing
import Tools

// MARK: - refreshTools 串行化：丢失更新回归守卫（D-16 **真因**，09-06）

//
// 判据形状：一组任务里「从注册表注销工具」与 6 次 refreshTools 并发；组结束后展示快照
// 必然不含已注销工具（串行链保证后到的刷新一定在前驱之后重新读注册表）。
//
// 变异实测（09-06，本机两轮，非推测）：
//   · 把 refreshTools 换回串行化**之前**的原实现（单次「读注册表 → 写快照」，无链）
//     ⇒ 本用例 **600/600 轮全红**＝已注销工具被旧快照写回列表，确定性复现；
//   · 串行化后 ⇒ **0/600** 绿。
//   ⇒ 这不是低概率竞态的统计守卫，而是确定性判别器：旧实现下每次必红。
// 用内存客户端（MockMCPClient），零子进程 ⇒ 600 轮仍在 0.4s 内，不影响门禁时长。
//
// 这条实测同时纠正了 D-16 的归因：症状「卸载后工具仍在列表、提高等待上限也失败」
// 的根因是 AppViewModel.refreshTools 的跨 actor-hop 读-改-写丢失更新（旧快照后写），
// 不是 MCP 子进程回收延迟。见 QUALITY_REPORT 09-06 补记㉕。

@MainActor
@Suite("AppViewModel 工具快照并发刷新", .serialized)
struct AppViewModelToolsRefreshRaceTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func makeVM() throws -> AppViewModel {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-tools-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AppViewModel(
            skillUserDirectory: dir.appendingPathComponent("skills"),
            sessionDBURL: dir.appendingPathComponent("s.sqlite"),
            mcpConfigURLOverride: dir.appendingPathComponent("servers.json")
        )
    }

    @Test("并发刷新不得把已注销工具写回展示快照（600 轮）")
    func concurrentRefreshNeverRevivesUnregisteredTools() async throws {
        let vm = try makeVM()
        var staleTrials = 0
        for trial in 0 ..< 600 {
            let serverName = "race\(trial)"
            let mock = MockMCPClient(name: serverName)
            await mock.addTool(MCPToolSpec(name: "one", description: "d", inputSchema: "{}")) { _ in "ok" }
            await vm.mcpManager.register(mock, descriptor: MCPServer(name: serverName, transport: "in-memory"))
            for tool in await vm.mcpManager.makeTools() {
                await vm.toolRegistry.register(tool)
            }
            await vm.refreshTools()
            let prefix = "mcp_\(serverName)_"
            let registered = vm.tools.contains { $0.name.hasPrefix(prefix) }
            if !registered {
                Issue.record("trial \(trial): 前置未成立，工具未出现在快照（实得 \(vm.tools.count) 项）")
                continue
            }
            // 三个动作并发：刷新 / 从注册表注销（含管理器摘除）/ 再刷新
            // 6 次并发刷新 + 1 次注销：制造 MainActor 续体拥塞，
            // 让「旧快照后写」的窗口尽可能被踩到（未串行化时命中率实测见本文件顶注）
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await vm.mcpManager.disconnect(name: serverName, into: vm.toolRegistry) }
                for _ in 0 ..< 6 {
                    group.addTask { await vm.refreshTools() }
                }
            }
            if vm.tools.contains(where: { $0.name.hasPrefix(prefix) }) {
                staleTrials += 1
            }
        }
        #expect(staleTrials == 0, "丢失更新 \(staleTrials)/600 轮：已注销工具被旧快照写回展示列表")
    }
}
