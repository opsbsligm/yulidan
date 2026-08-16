import Foundation
import ServiceContainer

/// 内置插件 — 真实注册到 PluginManager，UI 列表直接读取 PluginManager.list()
/// 每个插件对应一组已实现的基础能力（文件 / 终端）。

final class BuiltInFilesystemPlugin: Plugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    let manifest = PluginManifest(
        id: PluginID("file-system"),
        name: "文件系统",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "在用户本地文件系统中安全地读取、写入和列出文件。",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
        permissions: [.filesystemRead, .filesystemWrite]
    )
    var isActive: Bool { lock.withLock { _active } }
    func initialize(context: PluginContext) async throws {}
    func start(context: PluginContext) async throws { lock.withLock { _active = true } }
    func stop(context: PluginContext) async { lock.withLock { _active = false } }
}

final class BuiltInTerminalPlugin: Plugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    let manifest = PluginManifest(
        id: PluginID("terminal"),
        name: "终端",
        version: PluginVersion(major: 1, minor: 0, patch: 0),
        description: "通过 zsh 执行 Shell 命令并回传输出（具备真实执行能力）。",
        minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
        permissions: [.shellExecution, .terminalAccess]
    )
    var isActive: Bool { lock.withLock { _active } }
    func initialize(context: PluginContext) async throws {}
    func start(context: PluginContext) async throws { lock.withLock { _active = true } }
    func stop(context: PluginContext) async { lock.withLock { _active = false } }
}

/// 插件展示元信息目录（PluginInfo 不含描述/权限，UI 展示用）
enum BuiltInPluginCatalog {
    static let info: [String: (description: String, permissions: [String])] = [
        "file-system": (
            description: "在用户本地文件系统中安全地读取、写入和列出文件。",
            permissions: ["文件读取", "文件写入"]
        ),
        "terminal": (
            description: "通过 zsh 执行 Shell 命令并回传输出（具备真实执行能力）。",
            permissions: ["Shell 执行", "终端访问"]
        ),
    ]
}
