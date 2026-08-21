import Foundation
import ServiceContainer

// 内置插件 — 真实注册到 PluginManager，UI 列表直接读取 PluginManager.list()
// 每个插件对应一组已实现的基础能力（文件 / 终端）。

// MARK: - 内置演示主题插件（主题插件机制演示：ThemeProviderPlugin 交付规格；可像普通插件一样卸载）

// 注意：演示主题经插件机制交付，不属于“硬编码内置主题”；系统基准（systemBaseline）仅作回落。

public final class BuiltInOceanThemePlugin: ThemeProviderPlugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    public let manifest = PluginManifest(
        id: PluginID("theme-ocean"),
        name: "深海蓝主题",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "主题插件演示：深海蓝强调色 + 冷色调消息气泡。",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
    )
    public let themeSpec = ThemeSpec(
        id: "ocean",
        name: "深海蓝",
        accentHex: "#0A84FF",
        userMessageHex: "#0A84FF26",
        assistantMessageHex: "#0A84FF14",
        description: "深海蓝强调色与冷色气泡"
    )
    public init() {}

    public var isActive: Bool {
        lock.withLock { _active }
    }

    public func initialize(context _: PluginContext) async throws {}
    public func start(context _: PluginContext) async throws {
        lock.withLock { _active = true }
    }

    public func stop(context _: PluginContext) async {
        lock.withLock { _active = false }
    }
}

public final class BuiltInSunsetThemePlugin: ThemeProviderPlugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    public let manifest = PluginManifest(
        id: PluginID("theme-sunset"),
        name: "落日渐橙主题",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "主题插件演示：落日渐橙强调色 + 暖色调消息气泡。",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
    )
    public let themeSpec = ThemeSpec(
        id: "sunset",
        name: "落日渐橙",
        accentHex: "#FF9F0A",
        userMessageHex: "#FF9F0A26",
        assistantMessageHex: "#FF9F0A14",
        description: "落日渐橙强调色与暖色气泡"
    )
    public init() {}

    public var isActive: Bool {
        lock.withLock { _active }
    }

    public func initialize(context _: PluginContext) async throws {}
    public func start(context _: PluginContext) async throws {
        lock.withLock { _active = true }
    }

    public func stop(context _: PluginContext) async {
        lock.withLock { _active = false }
    }
}

/// 依赖演示插件（P0.4⑤ 依赖缺失 UI）：声明依赖「终端」插件 ≥1.0.0。
/// 仅上架本地市场（不随内置自动安装）：用户安装/卸载「终端」后可完整演示依赖满足/缺失两种 UI 状态。
public final class BuiltInTerminalPlusPlugin: Plugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    public let manifest = PluginManifest(
        id: PluginID("terminal-plus"),
        name: "终端增强（依赖演示）",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "依赖演示插件：依赖「终端」插件 ≥1.0.0；卸载终端后安装/更新本插件会触发依赖缺失提示。",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
        dependencies: [PluginDependency(id: PluginID("terminal"), minVersion: PluginVersion(major: 1, minor: 0, patch: 0), required: true)],
        permissions: [.clipboardAccess]
    )
    public init() {}

    public var isActive: Bool {
        lock.withLock { _active }
    }

    public func initialize(context _: PluginContext) async throws {}
    public func start(context _: PluginContext) async throws {
        lock.withLock { _active = true }
    }

    public func stop(context _: PluginContext) async {
        lock.withLock { _active = false }
    }
}

public final class BuiltInFilesystemPlugin: Plugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    public let manifest = PluginManifest(
        id: PluginID("file-system"),
        name: "文件系统",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "在用户本地文件系统中安全地读取、写入和列出文件。",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
        permissions: [.filesystemRead, .filesystemWrite]
    )
    public init() {}

    public var isActive: Bool {
        lock.withLock { _active }
    }

    public func initialize(context _: PluginContext) async throws {}
    public func start(context _: PluginContext) async throws {
        lock.withLock { _active = true }
    }

    public func stop(context _: PluginContext) async {
        lock.withLock { _active = false }
    }
}

public final class BuiltInTerminalPlugin: Plugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    public let manifest = PluginManifest(
        id: PluginID("terminal"),
        name: "终端",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "通过 zsh 执行 Shell 命令并回传输出（具备真实执行能力）。",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
        permissions: [.shellExecution, .terminalAccess]
    )
    public init() {}

    public var isActive: Bool {
        lock.withLock { _active }
    }

    public func initialize(context _: PluginContext) async throws {}
    public func start(context _: PluginContext) async throws {
        lock.withLock { _active = true }
    }

    public func stop(context _: PluginContext) async {
        lock.withLock { _active = false }
    }
}

/// 插件展示元信息目录（PluginInfo 不含描述/权限，UI 展示用）
public enum BuiltInPluginCatalog {
    public static let info: [String: (description: String, permissions: [String])] = [
        "file-system": (
            description: "在用户本地文件系统中安全地读取、写入和列出文件。",
            permissions: ["文件读取", "文件写入"]
        ),
        "terminal": (
            description: "通过 zsh 执行 Shell 命令并回传输出（具备真实执行能力）。",
            permissions: ["Shell 执行", "终端访问"]
        ),
        "terminal-plus": (
            description: "依赖演示插件：依赖「终端」插件 ≥1.0.0（P0.4⑤ 依赖缺失 UI 演示）。",
            permissions: ["剪贴板"]
        ),
    ]
}
