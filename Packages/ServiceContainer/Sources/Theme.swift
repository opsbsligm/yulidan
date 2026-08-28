import Foundation

/// 主题规格（主题插件交付的数据模型；App 渲染层负责解释）
///
/// 设计原则（铁律）：主题一律由主题插件运行时交付，App UI 代码不硬编码任何设计主题。
/// 本结构体仅是“主题的数据形状”；`systemBaseline` 为无主题可用时的系统回落基准（全 nil = 完全跟随系统外观），
/// 不是一个可设计的主题。
public struct ThemeSpec: Sendable, Codable, Equatable, Hashable {
    /// 主题唯一标识（插件定义；作为激活主题持久化键，必须全局唯一）
    public var id: String
    /// 展示名（设置面板主题选项显示）
    public var name: String
    /// 强调色 hex（如 "#0A84FF"）；nil = 系统强调色
    public var accentHex: String?
    /// 用户消息气泡色调 hex；nil = 系统默认
    public var userMessageHex: String?
    /// 助手消息气泡色调 hex；nil = 系统默认
    public var assistantMessageHex: String?
    /// 描述（可选；设置面板主题选项展示）
    public var description: String?

    // MARK: P1 预留 — 玻璃材质参数（P1 Liquid Glass 阶段由主题插件驱动生效）

    /// 玻璃 tint 色调 hex；nil = 系统默认
    public var glassTintHex: String?
    /// 玻璃材质档位 manifest 值（P1.4：`"regular"` / `"clear"`；nil 或未知值 = 默认 .regular 宽容回落，不破坏主题加载）
    public var glassMaterial: String?
    /// 模糊强度提示（0...1）；nil = 系统默认
    public var blurIntensity: Double?
    /// 高光强度提示（0...1）；nil = 系统默认
    public var highlightIntensity: Double?

    public init(
        id: String,
        name: String,
        accentHex: String? = nil,
        userMessageHex: String? = nil,
        assistantMessageHex: String? = nil,
        description: String? = nil,
        glassTintHex: String? = nil,
        glassMaterial: String? = nil,
        blurIntensity: Double? = nil,
        highlightIntensity: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.userMessageHex = userMessageHex
        self.assistantMessageHex = assistantMessageHex
        self.description = description
        self.glassTintHex = glassTintHex
        self.glassMaterial = glassMaterial
        self.blurIntensity = blurIntensity
        self.highlightIntensity = highlightIntensity
    }

    /// 系统基准（回落专用，非设计主题；全 nil = 完全跟随系统外观）
    public static let systemBaseline = ThemeSpec(id: "system-baseline", name: "系统基准")
}

/// 主题插件协议：声明 theme 能力的本地插件遵循本协议并交付规格
///
/// MCP 主题服务器走工具约定（暴露 `get_theme_spec` 工具返回 ThemeSpec JSON），
/// 见 App 层 ThemePluginManager 的识别逻辑。
public protocol ThemeProviderPlugin: Plugin {
    var themeSpec: ThemeSpec { get }
}
