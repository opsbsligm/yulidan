import Foundation
import MCP
import ServiceContainer
import SwiftUI

// MARK: - P0.4 主题插件机制（主题一律来自插件；系统基准仅作回落）

/// 单个主题选项（来源：系统基准 / 本地主题插件 / MCP 主题服务器）
struct ThemeOption: Identifiable, Hashable {
    enum Source: Hashable, Sendable {
        case systemBaseline
        case plugin(String) // PluginID rawValue
        case mcpServer(String) // 服务器名
    }

    let spec: ThemeSpec
    let source: Source
    /// 来源展示名（设置面板下拉项副标题）
    let sourceName: String

    var id: String {
        spec.id
    }

    var isSystem: Bool {
        if case .systemBaseline = source {
            return true
        }
        return false
    }
}

/// 主题插件管理器：发现主题插件、管理激活主题、来源消失时自动回落系统基准
///
/// 识别规则：
/// - 本地插件：遵循 ThemeProviderPlugin 且 active
/// - MCP 服务器：isAvailable 且暴露约定工具 `get_theme_spec`（返回 ThemeSpec JSON 文本）
@MainActor
final class ThemePluginManager {
    /// MCP 主题服务器工具约定名
    static let themeToolName = "get_theme_spec"
    /// 激活主题持久化键（UserDefaults）
    static let activeKey = "harness.themePluginID"

    private(set) var themes: [ThemeOption] = []
    private(set) var activeThemeID: String
    /// 最近一次回落原因（App 层消费后清 nil，用于 toast）
    var lastFallbackReason: String?

    private let pluginManager: PluginManager
    private let mcpManager: MCPServerManager

    init(pluginManager: PluginManager, mcpManager: MCPServerManager) {
        self.pluginManager = pluginManager
        self.mcpManager = mcpManager
        activeThemeID = UserDefaults.standard.string(forKey: Self.activeKey) ?? ThemeSpec.systemBaseline.id
    }

    var activeTheme: ThemeOption? {
        themes.first { $0.id == activeThemeID }
    }

    var activeSpec: ThemeSpec {
        activeTheme?.spec ?? .systemBaseline
    }

    /// 刷新主题选项（系统基准 + 本地主题插件 + MCP 主题服务器）
    /// 返回 true = 本次刷新发生了回落（原激活主题来源已消失）
    @discardableResult
    func refresh() async -> Bool {
        var options: [ThemeOption] = [
            ThemeOption(spec: .systemBaseline, source: .systemBaseline, sourceName: "系统基准（回落用）"),
        ]
        // 1) 本地主题插件（ThemeProviderPlugin 且 active）
        for plugin in await pluginManager.activePluginInstances() {
            guard let theme = plugin as? ThemeProviderPlugin else { continue }
            options.append(ThemeOption(
                spec: theme.themeSpec,
                source: .plugin(plugin.manifest.id.rawValue),
                sourceName: plugin.manifest.name
            ))
        }
        // 2) MCP 主题服务器（isAvailable 且 get_theme_spec 可调通并返回合法 ThemeSpec）
        for server in await mcpManager.servers() where server.isAvailable {
            guard let spec = await fetchMCPTheme(from: server.name) else { continue }
            options.append(ThemeOption(spec: spec, source: .mcpServer(server.name), sourceName: server.name))
        }
        // 同 id 去重（后加入者不覆盖先加入者，保证设置选择稳定）
        var seen = Set<String>()
        themes = options.filter { seen.insert($0.id).inserted }

        // 3) 回落：激活主题来源消失（插件卸载/停用、MCP 服务器断开/卸载）
        if activeTheme != nil {
            return false
        }
        let lostName = themes.first { $0.id == activeThemeID }?.spec.name
            ?? UserDefaults.standard.string(forKey: Self.activeKey) ?? activeThemeID
        activeThemeID = ThemeSpec.systemBaseline.id
        persistActive()
        lastFallbackReason = "主题「\(lostName)」不可用，已自动回落系统基准"
        return true
    }

    /// 切换激活主题（UI 观察 AppViewModel.activeThemeSpec 即时生效，无需重启）
    func apply(id: String) {
        guard themes.contains(where: { $0.id == id }) else { return }
        activeThemeID = id
        lastFallbackReason = nil
        persistActive()
    }

    // MARK: - 私有

    /// 调用 MCP 主题工具取规格；无该工具 / 调用失败 / 非法 JSON → nil（非主题服务器或暂不可用）
    private func fetchMCPTheme(from serverName: String) async -> ThemeSpec? {
        do {
            let raw = try await mcpManager.callTool(client: serverName, name: Self.themeToolName, arguments: [:])
            guard let data = raw.data(using: .utf8),
                  let spec = try? JSONDecoder().decode(ThemeSpec.self, from: data)
            else {
                return nil
            }
            // 与文件型主题包同一校验口径（id/name 非空 + 颜色合法 + 玻璃强度 0...1）：
            // 非法 spec = 视为非主题服务器 → 回落系统基准，不半生效（防假配置静默）
            do {
                try ThemePackageImporter.validate(spec)
            } catch {
                return nil
            }
            return spec
        } catch {
            return nil
        }
    }

    private func persistActive() {
        UserDefaults.standard.set(activeThemeID, forKey: Self.activeKey)
    }
}

// MARK: - 主题渲染辅助（hex 解析 + Environment 注入）

extension Color {
    /// 解析 "#RRGGBB" / "#AARRGGBB"；非法 → nil
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r: UInt64, g: UInt64, b: UInt64, a: UInt64
        if s.count == 8 {
            a = (value >> 24) & 0xFF
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        } else {
            a = 0xFF
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        }
        self = Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension ThemeSpec {
    /// 强调色（nil → 系统蓝基准）
    var accentColor: Color {
        Color(hex: accentHex) ?? .blue
    }

    /// 用户消息气泡色（nil → 系统默认基准）
    var userMessageColor: Color {
        Color(hex: userMessageHex) ?? HarnessTheme.userMessage
    }

    /// 助手消息气泡色（nil → 系统默认基准）
    var assistantMessageColor: Color {
        Color(hex: assistantMessageHex) ?? HarnessTheme.assistantMessage
    }
}

extension EnvironmentValues {
    /// 当前激活主题规格（根视图注入；主题切换时整体刷新）
    @Entry var harnessThemeSpec: ThemeSpec = .systemBaseline
}
