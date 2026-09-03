import Foundation
@testable import MCP
import XCTest

/// G4 层1「DSH 社区插件拿来即用」opt-in 实包实测（铁律 8：A 层进程内验证，零前台）。
///
/// 普查事实（docs/DSH_COMMUNITY_PLUGIN_CENSUS.md）：社区 MCP 依赖率仅 1%，4 个带 MCP 依赖的包里
/// 真 stdio server 仅 `@zseven-w/dsh-crew`（其余 3 个为 client/适配器/Cordis 插件壳，验身见补记㉛）。
/// 本测试用**我方宿主同款 StdioMCPClient**装载该真实社区包：只走 initialize + tools/list，
/// **永不调用 tools/call**（社区代码只被加载不被指挥）；HOME 指向沙箱目录、环境零密钥。
/// 默认跳过保持门禁确定性；`HARNESS_G4_LIVE=1` 且包路径存在时才执行（缺包 → 跳过非失败）。
final class MCPCommunityLiveTests: XCTestCase {
    func testLiveDshCrewCommunityServerLoadsViaOurClient() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["HARNESS_G4_LIVE"] == "1" else {
            throw XCTSkip("opt-in：export HARNESS_G4_LIVE=1（需本机解包社区插件，见 CENSUS 补记㉛）")
        }
        let pkgDir = env["HARNESS_G4_DSH_CREW_DIR"] ?? "/tmp/g4pkgs2/dsh-crew/package"
        let serverPath = (pkgDir as NSString).appendingPathComponent("src/server.mjs")
        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("社区包不存在：\(serverPath)")
        }
        let node = env["HARNESS_G4_NODE"] ?? "/opt/homebrew/bin/node"
        let sandboxHome = env["HARNESS_G4_SANDBOX_HOME"] ?? "/tmp/g4home"
        let client = StdioMCPClient(
            name: "dsh-crew-live",
            configuration: StdioMCPConfiguration(command: node,
                                                 arguments: [serverPath],
                                                 environment: ["HOME": sandboxHome],
                                                 startupTimeout: 20)
        )
        defer { Task { await client.stop() } }
        let tools = try await client.listTools()
        let names = Set(tools.map(\.name))
        XCTAssertGreaterThanOrEqual(tools.count, 6)
        XCTAssertTrue(names.contains("dsh_run_worker"), "工具表应含 dsh_run_worker，实得：\(names)")
        let caps = await client.capabilities()
        XCTAssertEqual(caps?.serverName, "dsh-crew")
    }
}
