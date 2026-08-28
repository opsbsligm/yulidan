import Combine
import Foundation
@testable import HarnessApp
import ServiceContainer
import SwiftUI
import Testing

// MARK: - P0.4 ⑥ 主题插件机制：发现 / 应用 / 持久化 / 回落 / MCP 主题服务器 e2e / hex 解析

//
// 隔离纪律：
// - mcpConfigURLOverride 为实例级测试缝（经 init 注入），每用例独立临时 URL
// - UserDefaults "harness.themePluginID" 每用例开头清理（防跨 suite 激活态泄漏）

@MainActor
@Suite("AppViewModel P0.4 主题插件机制", .serialized)
struct AppViewModelThemePluginTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func makeVM() -> (vm: AppViewModel, mcpConfigURL: URL) {
        let mcpConfigURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-theme-test-\(UUID().uuidString)")
            .appendingPathComponent("servers.json")
        UserDefaults.standard.removeObject(forKey: ThemePluginManager.activeKey)
        let vm = AppViewModel(
            skillUserDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-theme-skills-\(UUID().uuidString)"),
            sessionDBURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-theme-test-\(UUID().uuidString).sqlite"),
            mcpConfigURLOverride: mcpConfigURL
        )
        return (vm, mcpConfigURL)
    }

    // MARK: 用例 1：发现（系统基准 + 两个内置主题插件）

    @Test("refreshThemes 发现内置主题插件（baseline + ocean + sunset）")
    func discoversBuiltInThemePlugins() async {
        let (vm, _) = makeVM()

        await vm.loadPluginsInfrastructure()
        await vm.refreshThemes()

        let ids = Set(vm.themeOptions.map(\.id))
        #expect(ids.contains(ThemeSpec.systemBaseline.id))
        #expect(ids.contains("ocean"))
        #expect(ids.contains("sunset"))
        #expect(vm.activeThemeSpec == .systemBaseline)
        // 插件页数据源：主题插件打 isTheme 标
        #expect(vm.plugins.count(where: { $0.isTheme }) == 2)
    }

    // MARK: 用例 2：应用 + 持久化

    @Test("applyTheme 即时生效且持久化 UserDefaults")
    func applyPersists() async {
        let (vm, _) = makeVM()

        await vm.loadPluginsInfrastructure()
        await vm.refreshThemes()
        vm.applyTheme(id: "ocean")

        #expect(vm.activeThemeSpec.id == "ocean")
        #expect(vm.activeThemeSpec.accentHex == "#0A84FF")
        #expect(UserDefaults.standard.string(forKey: ThemePluginManager.activeKey) == "ocean")

        // 未知 id 不生效（guard 拦截）
        vm.applyTheme(id: "not-exists")
        #expect(vm.activeThemeSpec.id == "ocean")
    }

    // MARK: 用例 3：插件卸载 → 自动回落系统基准 + toast

    @Test("主题插件卸载后自动回落系统基准并提示")
    func fallbackAfterPluginUninstall() async throws {
        let (vm, _) = makeVM()

        await vm.loadPluginsInfrastructure()
        await vm.refreshThemes()
        vm.applyTheme(id: "ocean")
        #expect(vm.activeThemeSpec.id == "ocean")

        try await vm.pluginManager.uninstall(PluginID("theme-ocean"))
        await vm.refreshThemes()

        #expect(vm.activeThemeSpec == .systemBaseline)
        #expect(vm.toastMessage?.contains("回落") == true, "回落应 toast 提示：\(vm.toastMessage ?? "nil")")
        #expect(UserDefaults.standard.string(forKey: ThemePluginManager.activeKey) == ThemeSpec.systemBaseline.id)
    }

    // MARK: 用例 4：MCP 主题服务器 e2e（真实 stdio 子进程）

    @Test("MCP 主题服务器 e2e：导入→识别→应用→卸载回落")
    func mcpThemeServerE2E() async throws {
        let (vm, _) = makeVM()

        let script = try writeThemeMCPScript()
        defer { try? FileManager.default.removeItem(atPath: script) }

        await vm.importMCPServer(name: "theme-mcp", command: "/usr/bin/env",
                                 arguments: "python3 \(script)", environment: "")
        // importMCPServer 内部已完成 refreshThemes + refreshMCPServers
        #expect(vm.mcpServers.count == 1)
        #expect(vm.mcpServers.first?.isAvailable == true)
        #expect(vm.mcpServers.first?.isTheme == true, "MCP 列表应打主题徽章")

        let ids = Set(vm.themeOptions.map(\.id))
        #expect(ids.contains("mcp-mint"))
        #expect(vm.themeMCPServerNames.contains("theme-mcp"))

        vm.applyTheme(id: "mcp-mint")
        #expect(vm.activeThemeSpec.id == "mcp-mint")
        #expect(vm.activeThemeSpec.accentHex == "#34C759")

        // 卸载 MCP 服务器 → 主题来源消失 → 回落
        // toast 经 sink 捕获（2026-08-29 flaky 修复：toastMessage 2.5s 自动清除，
        // 并行 CI 高负载下 removeMCPServer 卸载后刷新超 2.5s → 直接读值已被清；sink 对发射时点不敏感）
        var toasts: [String] = []
        let sink = vm.$toastMessage.compactMap(\.self).removeDuplicates().sink { toasts.append($0) }
        if let item = vm.mcpServers.first {
            await vm.removeMCPServer(item)
        }
        sink.cancel()
        #expect(vm.activeThemeSpec == .systemBaseline)
        #expect(toasts.contains { $0.contains("回落") }, "卸载回落应通知，实际 toasts=\(toasts)")
    }

    // MARK: 用例 4b：MCP 非法主题 spec e2e（诚实闭环：越界玻璃强度 = 不识别为主题，不半生效）

    @Test("MCP 非法 spec e2e：blurIntensity=1.5 → 不识别为主题，回落基准")
    func mcpInvalidThemeSpecFallsBack() async throws {
        let (vm, _) = makeVM()

        let script = try writeThemeMCPScript(extraThemeField: "\"blurIntensity\": 1.5")
        defer { try? FileManager.default.removeItem(atPath: script) }

        await vm.importMCPServer(name: "bad-theme-mcp", command: "/usr/bin/env",
                                 arguments: "python3 \(script)", environment: "")
        // 服务器本身连通正常，但 spec 越界 = 视为非主题服务器（与文件包口径一致）
        #expect(vm.mcpServers.count == 1)
        #expect(vm.mcpServers.first?.isAvailable == true)
        #expect(vm.mcpServers.first?.isTheme != true, "越界 spec 不应打主题徽章")
        #expect(!vm.themeOptions.map(\.id).contains("mcp-mint"))
        #expect(vm.activeThemeSpec == .systemBaseline)
    }

    // MARK: 用例 5：hex 解析 + ThemeSpec 颜色回落

    @Test("Color(hex:) 合法/非法解析与 ThemeSpec 颜色回落")
    func colorHexParsing() {
        #expect(Color(hex: "#0A84FF") != nil)
        #expect(Color(hex: "#0A84FF26") != nil)
        #expect(Color(hex: "  #ff0000 ") != nil, "应容忍首尾空白")
        #expect(Color(hex: "0A84FF") == nil, "缺 # 前缀")
        #expect(Color(hex: "#0A84F") == nil, "长度 5 非法")
        #expect(Color(hex: "#GGGGGG") == nil, "非 hex 字符")
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: nil) == nil)

        // 全 nil 规格 → 系统基准色
        #expect(ThemeSpec.systemBaseline.accentColor == .blue)
        #expect(ThemeSpec(id: "t", name: "n").userMessageColor == HarnessTheme.userMessage)
        #expect(ThemeSpec(id: "t", name: "n").assistantMessageColor == HarnessTheme.assistantMessage)
        // 提供 hex 的规格 → 生效为自定义色
        let mint = ThemeSpec(id: "m", name: "m", accentHex: "#34C759")
        #expect(mint.accentColor != .blue)
    }

    // MARK: 工具

    /// 写一个最小 MCP stdio 主题服务器（暴露 get_theme_spec，返回 ThemeSpec JSON 文本）
    private func writeThemeMCPScript(extraThemeField: String? = nil) throws -> String {
        var source = themeMCPServerSource
        if let extraThemeField {
            // 锚点 = THEME 字典 description 行（文件内唯一）：追加额外字段（如越界 blurIntensity）
            let anchor = #"    "description": "fake MCP theme server""#
            let patched = anchor + ",\n    " + extraThemeField
            #expect(source.replacingOccurrences(of: anchor, with: patched) != source)
            source = source.replacingOccurrences(of: anchor, with: patched)
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-theme-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("theme_server.py").path
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}

// MARK: - 内嵌 MCP 主题服务器脚本（文件作用域：swiftformat indent 规则对嵌套多行字符串误报，与 MCPProtocolExtensionTests 同构）

private let themeMCPServerSource = #"""
import json, sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


THEME = {
    "id": "mcp-mint",
    "name": "MCP 薄荷绿",
    "accentHex": "#34C759",
    "userMessageHex": "#34C75926",
    "assistantMessageHex": "#34C75914",
    "description": "fake MCP theme server"
}


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
            send({"jsonrpc": "2.0", "id": mid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "theme-mcp-fake", "version": "1.0.0"}}})
        elif method == "notifications/initialized":
            pass
        elif method == "ping":
            send({"jsonrpc": "2.0", "id": mid, "result": {}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": [
                {"name": "get_theme_spec", "description": "theme spec",
                 "inputSchema": {"type": "object"}}]}})
        elif method == "tools/call":
            if params.get("name") == "get_theme_spec":
                send({"jsonrpc": "2.0", "id": mid, "result": {
                    "content": [{"type": "text", "text": json.dumps(THEME)}]}})
            else:
                send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": "unknown tool"}})


if __name__ == "__main__":
    main()
"""#
