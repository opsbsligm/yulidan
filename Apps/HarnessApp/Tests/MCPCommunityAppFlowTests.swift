import Foundation
@testable import HarnessApp
import MCP
import XCTest

// MARK: - G4「拿来即用」App 真实链路实测（层1 升级：从宿主客户端直连 → AppViewModel 全链路）

//
// 与 MCPCommunityLiveTests（MCP 包级，StdioMCPClient 直连）互补：本测试走 **App 用户同款的
// 全链路**——importMCPServer（写 servers.json，与真实用户同一配置格式/同一函数）→
// mcpManager.connectStdio（运行时连接链路）→ 展示层 MCPDisplayItem（toolCount/serverInfo/
// isAvailable）→ removeMCPServer（卸载 + 断开子进程）。证明社区包在「用户导入框里粘一行命令」
// 的同一代码路径上拿来即用。
//
// 安全姿态与层1 一致：零 tools/call（连接+列表由 import 内部完成，不指挥社区代码）；
// HOME 指沙箱、环境零密钥；配置/DB 全部临时目录（实例级测试缝，绝不触真实 ~/.harness）。
// opt-in：`HARNESS_G4_LIVE=1` 且包在位才跑（默认 skip 保门禁确定性，与补记㉛同构）。

@MainActor
final class MCPCommunityAppFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppViewModel.notificationServiceFactory = { NoopNotificationService() } // 幂等：门禁用例间重复赋值无害
    }

    @MainActor
    private static func makeVM() -> (vm: AppViewModel, mcpConfigURL: URL) {
        let mcpConfigURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-g4-appflow-\(UUID().uuidString)")
            .appendingPathComponent("servers.json")
        let vm = AppViewModel(
            skillUserDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-g4-appflow-skills-\(UUID().uuidString)"),
            sessionDBURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-g4-appflow-\(UUID().uuidString).sqlite"),
            mcpConfigURLOverride: mcpConfigURL
        )
        return (vm, mcpConfigURL)
    }

    /// dsh-crew 全链路：导入→连接→6+工具在册→卸载归零（与真实用户同一 servers.json 格式）
    func testCommunityServerViaAppFullFlow() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["HARNESS_G4_LIVE"] == "1" else {
            throw XCTSkip("opt-in：export HARNESS_G4_LIVE=1（需本机解包社区插件，见 CENSUS 复现手册）")
        }
        let pkgDir = env["HARNESS_G4_DSH_CREW_DIR"] ?? "/tmp/g4pkgs2/dsh-crew/package"
        let serverPath = (pkgDir as NSString).appendingPathComponent("src/server.mjs")
        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("社区包不存在：\(serverPath)")
        }
        let node = env["HARNESS_G4_NODE"] ?? "/opt/homebrew/bin/node"
        let sandboxHome = env["HARNESS_G4_SANDBOX_HOME"] ?? "/tmp/g4home"

        let (vm, mcpURL) = await Self.makeVM()
        // ① 导入 = 用户在插件页表单填的同一函数/同一配置格式（拿来即用的「装」）
        await vm.importMCPServer(name: "dsh-crew-appflow", command: node,
                                 arguments: serverPath, environment: "HOME=\(sandboxHome)")
        // ② 配置落盘（真实用户 servers.json 同一序列化格式）
        let configs = MCPDiscovery.loadConfigs(url: mcpURL)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs.first?.command, node)
        // ③ 运行时连接 + 展示层在册（「拿过来能直接用」的可见证据）
        XCTAssertEqual(vm.mcpServers.count, 1)
        let item = try XCTUnwrap(vm.mcpServers.first)
        XCTAssertTrue(item.isAvailable, "dsh-crew 应经 App 真实链路连接成功（失败会置 toolsLoadWarning）")
        XCTAssertGreaterThanOrEqual(item.toolCount ?? 0, 6, "工具数应 ≥6（层1 矩阵在册 6 工具），实得 \(String(describing: item.toolCount))")
        XCTAssertTrue(item.serverInfo?.contains("dsh-crew") == true, "serverInfo 应含上游 serverName dsh-crew")
        XCTAssertTrue(vm.tools.contains { $0.name.contains("dsh_run_worker") }, "工具注册表应含 dsh_run_worker")
        // ④ 卸载 = 配置移除 + 子进程断开（不留孤儿进程）
        await vm.removeMCPServer(item)
        XCTAssertTrue(vm.mcpServers.isEmpty)
        XCTAssertTrue(MCPDiscovery.loadConfigs(url: mcpURL).isEmpty)
    }
}
