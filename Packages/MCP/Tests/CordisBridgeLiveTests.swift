import Foundation
@testable import MCP
import XCTest

/// G4c 层2「Cordis 社区插件 sidecar」opt-in 冒烟（铁律 8：A 层，零前台）。
///
/// 用我方在册宿主 `StdioMCPClient` 直连 cordis-bridge（env -i 白名单 + fixture 插件），
/// 断言 initialize 握手 + tools/list 含 fixture 工具。只 list 不 call fixture 之外的包。
/// 默认跳过保门禁确定性；`HARNESS_G4C_LIVE=1` 时执行（bridge 源缺失 → 跳过非失败）。
/// 设计/实录：docs/G4C_SIDECAR_DESIGN.md §7–§8。
final class CordisBridgeLiveTests: XCTestCase {
    func testBridgeHandshakeAndFixtureTools() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["HARNESS_G4C_LIVE"] == "1" else {
            throw XCTSkip("opt-in：export HARNESS_G4C_LIVE=1（需 tools/cordis-bridge 已 npm install）")
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // MCP
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
        let bridgeDir = env["DSH_CORDIS_BRIDGE_SRC"]
            .map { URL(fileURLWithPath: $0) }
            ?? repoRoot.appendingPathComponent("tools/cordis-bridge", isDirectory: true)
        let bridgeJS = bridgeDir.appendingPathComponent("bridge.js")
        let fixture = bridgeDir.appendingPathComponent("fixtures/echo-plugin.mjs")
        guard FileManager.default.fileExists(atPath: bridgeJS.path),
              FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("bridge 源缺失或未安装依赖：\(bridgeJS.path)")
        }
        let node = env["HARNESS_G4_NODE"] ?? "/opt/homebrew/bin/node"
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("g4c-test-sandbox")
        // env 洗刷口径与 CLI probe 一致：/usr/bin/env -i 白名单
        let client = StdioMCPClient(
            name: "g4c-bridge-smoke",
            configuration: StdioMCPConfiguration(
                command: "/usr/bin/env",
                arguments: ["-i", "HOME=\(NSHomeDirectory())", "PATH=/usr/bin:/bin", node, bridgeJS.path,
                            "--sandbox", sandbox.path, fixture.absoluteURL.absoluteString],
                startupTimeout: 30
            )
        )
        defer { Task { await client.stop() } }
        do {
            try await client.start()
        } catch {
            let stderr = await client.recentStderr
            XCTFail("bridge 握手失败：\(error)\nstderr: \(stderr.suffix(800))")
            return
        }
        let tools = try await client.listTools()
        XCTAssertTrue(tools.contains { $0.name == "bridge_fixture_echo" },
                      "fixture 工具应可见，实际：\(tools.map(\.name))")
    }
}
