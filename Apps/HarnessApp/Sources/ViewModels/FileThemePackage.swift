import Foundation
import ServiceContainer

// MARK: - 文件型主题包（P0.4.3 DSH 社区主题包兼容）

// 主题包 = ThemeSpec JSON（单文件 .json 或目录内 spec.json）；导入后落活动工作区
// themes/<id>/spec.json（iCloud 模式 = iCloud Documents 容器，资源随工作区路由）。
// 导入产物是 ThemeProviderPlugin 实例（走标准插件生命周期：可卸载/停用），
// 主题来源仍是插件机制（铁律 5：UI 代码不硬编码主题）。

public enum ThemePackageError: LocalizedError, Equatable {
    case notAFile
    case missingSpec
    case invalidJSON(String)
    case invalidID
    case invalidColor(String)

    public var errorDescription: String? {
        switch self {
        case .notAFile:
            "主题包需为 .json 文件（或包含 spec.json 的目录）"
        case .missingSpec:
            "主题包中未找到 spec.json"
        case let .invalidJSON(detail):
            "spec.json 非法：\(detail)"
        case .invalidID:
            "主题 id 非法（需非空，最长 40 字符）"
        case let .invalidColor(value):
            "颜色值非法（需 #RRGGBB 或 #AARRGGBB）：\(value)"
        }
    }
}

/// 文件型主题包插件：spec 从磁盘 spec.json 加载（构造时一次性加载并校验）
public final class FileThemePackagePlugin: ThemeProviderPlugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false

    public let manifest: PluginManifest
    public let spec: ThemeSpec
    /// spec.json 路径（卸载时删除整个包目录）
    public let specURL: URL

    public var themeSpec: ThemeSpec {
        spec
    }

    public var isActive: Bool {
        lock.withLock { _active }
    }

    public init(spec: ThemeSpec, specURL: URL) {
        self.spec = spec
        self.specURL = specURL
        manifest = PluginManifest(
            id: PluginID(FileThemePackagePlugin.pluginID(for: spec.id)),
            name: spec.name,
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "文件型主题包（社区主题包兼容）：\(spec.description ?? spec.name)",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
        )
    }

    /// 插件 id 前缀（元数据清单 origin 判定 + 包目录名还原）
    public static func pluginID(for themeID: String) -> String {
        "theme-file-\(themeID)"
    }

    public func initialize(context _: PluginContext) async throws {}

    public func start(context _: PluginContext) async throws {
        lock.withLock { _active = true }
    }

    public func stop(context _: PluginContext) async {
        lock.withLock { _active = false }
    }
}

public enum ThemePackageImporter {
    /// 校验 hex 颜色（与 Color(hex:) 口径一致：#RRGGBB / #AARRGGBB）
    nonisolated static func isValidHex(_ value: String) -> Bool {
        guard value.hasPrefix("#") else { return false }
        let hex = value.dropFirst()
        guard [6, 8].contains(hex.count) else { return false }
        return hex.allSatisfy(\.isHexDigit)
    }

    /// 从文件/目录解析 spec（不写盘）
    public static func parse(fileURL: URL) throws -> ThemeSpec {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
            throw ThemePackageError.notAFile
        }
        let specURL: URL
        if isDir.boolValue {
            let candidate = fileURL.appendingPathComponent("spec.json")
            guard fm.fileExists(atPath: candidate.path) else { throw ThemePackageError.missingSpec }
            specURL = candidate
        } else {
            specURL = fileURL
        }
        let data: Data
        do {
            data = try Data(contentsOf: specURL)
        } catch {
            throw ThemePackageError.invalidJSON(error.localizedDescription)
        }
        let spec: ThemeSpec
        do {
            spec = try JSONDecoder().decode(ThemeSpec.self, from: data)
        } catch {
            throw ThemePackageError.invalidJSON(error.localizedDescription)
        }
        try validate(spec)
        return spec
    }

    /// 二次校验（工具输出校验口径）：id/name 非空 + 颜色合法
    public nonisolated static func validate(_ spec: ThemeSpec) throws {
        guard !spec.id.trimmingCharacters(in: .whitespaces).isEmpty, spec.id.count <= 40 else {
            throw ThemePackageError.invalidID
        }
        guard !spec.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ThemePackageError.invalidID
        }
        for color in [spec.accentHex, spec.userMessageHex, spec.assistantMessageHex] {
            guard let color else { continue } // nil = 系统默认（合法）
            guard isValidHex(color) else { throw ThemePackageError.invalidColor(color) }
        }
    }

    /// 导入主题包 → 落 themes/<id>/spec.json（原子写）+ 返回插件实例（调用方负责 install）
    @discardableResult
    public static func importPackage(fileURL: URL, into themesRoot: URL) throws -> FileThemePackagePlugin {
        let spec = try parse(fileURL: fileURL)
        let sanitized = sanitizeID(spec.id)
        var fixed = spec
        fixed.id = sanitized
        let dir = themesRoot.appendingPathComponent(sanitized, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let specURL = dir.appendingPathComponent("spec.json")
        let data = try JSONEncoder().encode(fixed)
        let temp = dir.appendingPathComponent(".spec-\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        defer { try? fm.removeItem(at: temp) }
        if fm.fileExists(atPath: specURL.path) {
            try fm.removeItem(at: specURL)
        }
        try fm.moveItem(at: temp, to: specURL)
        return FileThemePackagePlugin(spec: fixed, specURL: specURL)
    }

    /// 扫描 themes/ 下全部有效主题包（启动/切根时重建文件型主题插件）
    public static func loadAll(in themesRoot: URL) -> [FileThemePackagePlugin] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: themesRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [FileThemePackagePlugin] = []
        for item in items {
            let specURL = item.appendingPathComponent("spec.json")
            guard fm.fileExists(atPath: specURL.path),
                  let data = try? Data(contentsOf: specURL),
                  let spec = try? JSONDecoder().decode(ThemeSpec.self, from: data),
                  (try? validate(spec)) != nil
            else {
                continue
            }
            result.append(FileThemePackagePlugin(spec: spec, specURL: specURL))
        }
        return result.sorted { $0.manifest.name < $1.manifest.name }
    }

    /// 卸载删除包目录（themes/<id>/ 整体移除）
    public static func remove(themeID: String, from themesRoot: URL) {
        let dir = themesRoot.appendingPathComponent(sanitizeID(themeID), isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    /// id 净化（小写字母/数字/-/_；其余 → -；首尾去 -；上限 40）
    public nonisolated static func sanitizeID(_ raw: String) -> String {
        let lower = raw.lowercased()
        let map = lower.map { char -> String in
            char.isLetter || char.isNumber || char == "-" || char == "_" ? String(char) : "-"
        }.joined()
        var trimmed = Substring(map)
        while trimmed.hasPrefix("-") {
            trimmed = trimmed.dropFirst()
        }
        while trimmed.hasSuffix("-") {
            trimmed = trimmed.dropLast()
        }
        return String(trimmed.prefix(40))
    }
}
