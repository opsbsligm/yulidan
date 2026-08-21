import Foundation

// MARK: - 插件元数据清单（P0.1.5 / P0.4.4）

// iCloud 模式同步插件元数据、启用状态、配置；MCP 二进制不同步（仅记录本地路径引用，
// 其他设备缺失时进入「需重新导入」提示，不静默失败）。

public struct PluginMetaEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Origin: String, Codable, Sendable {
        case builtin
        case marketplace
        case localMCP
        case fileThemePackage
    }

    public var id: String
    public var name: String
    public var version: String
    public var origin: Origin
    /// 用户启用意图（true = 用户希望该插件/服务器处于启用态；连接态等瞬态信息不入清单）
    public var enabled: Bool
    /// 本地二进制/资源路径引用（仅记录，文件本身不同步；nil = 无本地路径概念）
    public var localPath: String?
    /// MCP 服务器启动命令（[command] + arguments；元数据，二进制不同步）
    public var mcpCommand: [String]?

    public init(
        id: String,
        name: String,
        version: String,
        origin: Origin,
        enabled: Bool,
        localPath: String? = nil,
        mcpCommand: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.origin = origin
        self.enabled = enabled
        self.localPath = localPath
        self.mcpCommand = mcpCommand
    }
}

public struct PluginMetaManifest: Codable, Equatable, Sendable {
    public static let version = 1
    public var version: Int
    public var plugins: [PluginMetaEntry]

    public init(version: Int = Self.version, plugins: [PluginMetaEntry] = []) {
        self.version = version
        self.plugins = plugins
    }
}

public enum PluginMetadataStore {
    /// 加载（缺失/损坏 → 空清单；离线优先，清单损坏不得污染运行时状态）
    public static func load(from url: URL) -> PluginMetaManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PluginMetaManifest()
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(PluginMetaManifest.self, from: data)
            guard decoded.version == PluginMetaManifest.version else { return PluginMetaManifest() }
            return decoded
        } catch {
            return PluginMetaManifest()
        }
    }

    /// 原子保存（临时文件 + replaceItem；写入失败抛错由调用方 toast）
    @discardableResult
    public static func save(_ manifest: PluginMetaManifest, to url: URL) throws -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".installed-\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        do {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: temp, to: url)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        return url
    }
}
