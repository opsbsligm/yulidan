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
    @MainActor
    private static func makeVM() -> (vm: AppViewModel, mcpConfigURL: URL) {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() } // 隔离上下文内注入（XCTestCase.setUp 非隔离，赋值放这里免非隔离告警；用例间重复赋值无害）
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

        let (vm, mcpURL) = Self.makeVM()
        // ① 导入 = 用户在插件页表单填的同一函数/同一配置格式（拿来即用的「装」）
        await vm.importMCPServer(name: "dsh-crew-appflow", command: node,
                                 arguments: serverPath, environment: "HOME=\(sandboxHome)")
        // ② 配置落盘（真实用户 servers.json 同一序列化格式）
        let configs = MCPDiscovery.loadConfigs(url: mcpURL)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs.first?.command, node)
        // ③ 运行时连接 + 展示层在册（「拿过来能直接用」的可见证据）
        XCTAssertEqual(vm.userMCPServers.count, 1)
        let item = try XCTUnwrap(vm.userMCPServer(named: "dsh-crew-appflow"))
        XCTAssertTrue(item.isAvailable, "dsh-crew 应经 App 真实链路连接成功（失败会置 toolsLoadWarning）")
        XCTAssertGreaterThanOrEqual(item.toolCount ?? 0, 6, "工具数应 ≥6（层1 矩阵在册 6 工具），实得 \(String(describing: item.toolCount))")
        XCTAssertTrue(item.serverInfo?.contains("dsh-crew") == true, "serverInfo 应含上游 serverName dsh-crew")
        XCTAssertTrue(vm.tools.contains { $0.name.contains("dsh_run_worker") }, "工具注册表应含 dsh_run_worker")
        // ④ 卸载 = 配置移除 + 子进程断开（不留孤儿进程）
        await vm.removeMCPServer(item)
        XCTAssertTrue(vm.userMCPServers.isEmpty)
        XCTAssertTrue(MCPDiscovery.loadConfigs(url: mcpURL).isEmpty)
    }

    /// 升级回路实测：同名导入（= 更新）指向新版包路径 → 重连后 serverInfo 从 rc.6 翻到 rc.7。
    /// 上游 `dsh plugin` 的 "update activates" 语义（安装态 reconcile）在我方的等价路径：
    /// 命令指向磁盘路径 → 包更新（npm 装到新版路径）→ 同名再导入即激活新代码。
    /// serverInfo 内嵌版本号提供不可伪造的「真的换了新二进制」判别（rc.6/rc.7 探针实测区分在册）。
    func testCommunityServerUpgradeActivatesViaSameNameImport() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["HARNESS_G4_LIVE"] == "1",
                          "opt-in：export HARNESS_G4_LIVE=1（需 rc.6/rc.7 双版本解包，见 CENSUS 升级复现）")
        let rc6 = env["HARNESS_G4_DSH_CREW_RC6_DIR"] ?? "/tmp/g4pkgs3/dsh-crew-rc6-x/package"
        let rc7 = env["HARNESS_G4_DSH_CREW_DIR"] ?? "/tmp/g4pkgs2/dsh-crew/package"
        let p6 = (rc6 as NSString).appendingPathComponent("src/server.mjs")
        let p7 = (rc7 as NSString).appendingPathComponent("src/server.mjs")
        for path in [p6, p7] where !FileManager.default.fileExists(atPath: path) {
            throw XCTSkip("社区包版本缺失：\(path)")
        }
        let node = env["HARNESS_G4_NODE"] ?? "/opt/homebrew/bin/node"
        let sandboxHome = env["HARNESS_G4_SANDBOX_HOME"] ?? "/tmp/g4home"

        let (vm, _) = Self.makeVM()
        // ① 旧版装载：serverInfo 必须是 rc.6（前置断言，防两路径同包假绿）
        await vm.importMCPServer(name: "dsh-crew-upgrade", command: node,
                                 arguments: p6, environment: "HOME=\(sandboxHome)")
        let old = try XCTUnwrap(vm.userMCPServer(named: "dsh-crew-upgrade"))
        XCTAssertTrue(old.isAvailable && old.serverInfo?.contains("0.1.0-rc.6") == true,
                      "前置：rc.6 装载应可用且 serverInfo 含 rc.6，实得 \(String(describing: old.serverInfo))")
        // ② 同名导入 = 更新 → 重连激活新代码路径：serverInfo 翻到 rc.7（同名 id 不变在 AppViewModelMCPServerTests 在册）
        await vm.importMCPServer(name: "dsh-crew-upgrade", command: node,
                                 arguments: p7, environment: "HOME=\(sandboxHome)")
        let upgraded = try XCTUnwrap(vm.userMCPServer(named: "dsh-crew-upgrade"))
        XCTAssertEqual(vm.userMCPServers.count, 1, "同名更新不得产生第二条目")
        XCTAssertTrue(upgraded.isAvailable && upgraded.serverInfo?.contains("0.1.0-rc.7") == true,
                      "升级回路：serverInfo 应翻至 rc.7（新包激活铁证），实得 \(String(describing: upgraded.serverInfo))")
        XCTAssertGreaterThanOrEqual(upgraded.toolCount ?? 0, 6)
    }
}
