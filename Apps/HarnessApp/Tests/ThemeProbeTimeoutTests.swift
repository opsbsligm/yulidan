import Foundation
@testable import HarnessApp
import MCP
import ServiceContainer
import Testing

// MARK: - D-22(a)：MCP 主题探测改用 2s 短超时（不再按 requestTimeout=30s 冻住导入/卸载）

//
// 判据口径：本组用例**不测墙钟**，测的是「探测调用是否携带短超时」＋「超时原因是否可诊断」。
// 墙钟面（2s 生效 vs 30s 生效）由 StdioMCPClient 层的 callTool(timeout:) 语义保证
// （见 Packages/MCP/Tests/MCPInboundFIFOTests.swift 同层用例 + MCPTests 超时用例）。

/// 记录探测参数的内存客户端（无真实传输 ⇒ 零墙钟）
private actor RecordingThemeClient: MCPClient {
    let name: String
    private let behaviour: Behaviour
    private(set) var capturedTimeout: TimeInterval?
    private(set) var callCount = 0

    enum Behaviour {
        /// 不回主题工具（等价于「一台不回应 tools/call 的服务器」）
        case timeout
        /// 返回合法 ThemeSpec
        case validSpec
    }

    init(name: String, behaviour: Behaviour) {
        self.name = name
        self.behaviour = behaviour
    }

    func listTools() async throws -> [MCPToolSpec] {
        [MCPToolSpec(name: ThemePluginManager.themeToolName, description: "theme", inputSchema: "{}")]
    }

    func callTool(name: String, arguments: [String: String]) async throws -> String {
        try await callTool(name: name, arguments: arguments, timeout: nil)
    }

    func callTool(name _: String, arguments _: [String: String], timeout: TimeInterval?) async throws -> String {
        capturedTimeout = timeout
        callCount += 1
        switch behaviour {
        case .timeout:
            throw MCPError.requestTimeout("超过 \(Int(timeout ?? -1))s 未响应")
        case .validSpec:
            return #"{"id":"mcp-mint","name":"Mint","description":"probe theme"}"#
        }
    }
}

@MainActor
@Suite("D-22 主题探测短超时")
struct ThemeProbeTimeoutTests {
    private func register(_ client: any MCPClient) async -> MCPServerManager {
        let mcp = MCPServerManager()
        await mcp.register(client, descriptor: MCPServer(name: client.name, transport: "in-memory", isAvailable: true))
        return mcp
    }

    @Test("探测调用必须携带 2s 短超时（不得沿用 requestTimeout=30）")
    func probeUsesShortTimeout() async {
        UserDefaults.standard.removeObject(forKey: ThemePluginManager.activeKey)
        let client = RecordingThemeClient(name: "theme-mcp", behaviour: .timeout)
        let mcp = await register(client)
        let manager = ThemePluginManager(
            pluginManager: PluginManager(container: ServiceContainer(), eventBus: EventBus()),
            mcpManager: mcp
        )

        await manager.refresh()

        let captured = await client.capturedTimeout
        #expect(captured == ThemePluginManager.themeProbeTimeout,
                "主题探测未传短超时（实际 \(String(describing: captured)) ⇒ 会退回 30s 冻结面)")
        #expect(captured == 2)
    }

    @Test("超时＝判为非主题服务器，并写可诊断原因（含误判代价的明示）")
    func timeoutWritesDiagnosticReason() async {
        UserDefaults.standard.removeObject(forKey: ThemePluginManager.activeKey)
        let client = RecordingThemeClient(name: "slow-mcp", behaviour: .timeout)
        let mcp = await register(client)
        let manager = ThemePluginManager(
            pluginManager: PluginManager(container: ServiceContainer(), eventBus: EventBus()),
            mcpManager: mcp
        )

        await manager.refresh()

        #expect(!manager.themes.map(\.id).contains("mcp-mint"), "超时的服务器不得进入主题候选")
        let reason = manager.probeDiagnostics["slow-mcp"]
        #expect(reason != nil, "超时须留可诊断原因")
        #expect(reason?.contains("2s 未应答") == true, "原因需含超时时长，实际：\(reason ?? "nil")")
        #expect(reason?.contains("误判") == true, "原因需写明误判代价，实际：\(reason ?? "nil")")
    }

    @Test("探测成功后清除该服务器旧诊断（不留陈旧原因）")
    func successClearsDiagnostic() async {
        UserDefaults.standard.removeObject(forKey: ThemePluginManager.activeKey)
        let client = RecordingThemeClient(name: "good-mcp", behaviour: .validSpec)
        let mcp = await register(client)
        let manager = ThemePluginManager(
            pluginManager: PluginManager(container: ServiceContainer(), eventBus: EventBus()),
            mcpManager: mcp
        )

        await manager.refresh()

        #expect(manager.themes.contains { $0.id == "mcp-mint" })
        #expect(manager.probeDiagnostics["good-mcp"] == nil)
    }
}
