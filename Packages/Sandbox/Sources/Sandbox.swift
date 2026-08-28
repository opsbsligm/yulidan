import Foundation

// MARK: - 错误

/// 路径沙箱错误
public enum PathSandboxError: Error, Sendable, CustomStringConvertible {
    /// 目标路径解析后落在所有允许根目录之外
    case outsideSandbox(attempted: String, allowedRoots: [String])
    /// 输入为空路径
    case emptyPath

    public var description: String {
        switch self {
        case let .outsideSandbox(attempted, roots):
            "路径 \(attempted) 超出沙箱允许范围：\(roots.joined(separator: ", "))"
        case .emptyPath:
            "路径不能为空"
        }
    }
}

// MARK: - PathSandbox

/// 路径沙箱：把文件访问限制在指定根目录内
///
/// 规则：
/// - `~` 展开 + 词法标准化（含 `..` 归约），`..` 无法越过已解析的根；
/// - 已存在路径做符号链接解析，防止「沙箱内符号链接指向外部」逃逸；
/// - 尚不存在的目标（写入场景）在「最长存在的祖先目录」处解析符号链接后拼接剩余段。
///
/// 用法：`try sandbox.assertAllowed(path)` 或 `sandbox.resolve(path)` + `sandbox.isAllowed(_:)`。
public struct PathSandbox: Sendable {
    /// 允许的根目录（init 时已标准化并解析符号链接）
    public let allowedRoots: [URL]

    public init(allowedRoots: [String]) {
        self.allowedRoots = allowedRoots.map {
            Self.canonical(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath))
        }
    }

    /// 把用户输入路径解析为规范形式（词法归约 + 符号链接解析）。空路径按当前目录处理。
    public func resolve(_ path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        // 空路径 = 当前目录。用绝对规范 CWD（而非相对 "."）：符号链接 CWD（如 /tmp→/private/tmp）下
        // 相对路径 canonical 结果会与 FileManager.currentDirectoryPath 分叉（xcodebuild 实测）
        let raw = trimmed.isEmpty
            ? FileManager.default.currentDirectoryPath
            : (trimmed as NSString).expandingTildeInPath
        return Self.canonical(URL(fileURLWithPath: raw))
    }

    /// 判断（解析后的）路径是否位于任一允许根目录内
    public func isAllowed(_ path: String) -> Bool {
        isAllowedURL(resolve(path))
    }

    /// 解析路径；若落在沙箱外则抛出 outsideSandbox
    public func assertAllowed(_ path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw PathSandboxError.emptyPath
        }
        let url = resolve(trimmed)
        guard isAllowedURL(url) else {
            throw PathSandboxError.outsideSandbox(attempted: path, allowedRoots: allowedRoots.map(\.path))
        }
    }

    private func isAllowedURL(_ url: URL) -> Bool {
        allowedRoots.contains { root in
            url.path == root.path || url.path.hasPrefix(root.path + "/")
        }
    }

    /// 规范化：存在 → realpath(3) 内核级全符号链接解析；不存在 → 最长存在祖先 realpath 后拼接剩余段
    /// 铁律 1 注记（2026-08-29 探针实锤，/tmp/canonicalprobe）：macOS 26/27 beta 上
    /// `standardizedFileURL` 会把 /private/tmp 反向别名为 /tmp，且 `resolvingSymlinksInPath()`
    /// 不还原该别名 → 组合后规范形漂移（xcodebuild CWD=/tmp 实测测试分叉）；
    /// realpath(3) 对 /tmp→/private/tmp、/private/tmp→/private/tmp 均返回内核规范形
    private static func canonical(_ url: URL) -> URL {
        let fm = FileManager.default
        let standardized = url.standardizedFileURL
        if let resolved = Self.realpath(standardized.path) {
            return URL(fileURLWithPath: resolved)
        }
        // 不存在的目标：向上找到最长存在的祖先
        var ancestor = standardized
        while !fm.fileExists(atPath: ancestor.path) {
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path {
                break
            }
            ancestor = parent
        }
        let resolvedAncestor = Self.realpath(ancestor.path) ?? ancestor.path
        let suffix = String(standardized.path.dropFirst(ancestor.path.count).drop(while: { $0 == "/" }))
        return suffix.isEmpty
            ? URL(fileURLWithPath: resolvedAncestor)
            : URL(fileURLWithPath: resolvedAncestor).appendingPathComponent(suffix)
    }

    /// realpath(3)：内核级全符号链接解析（绝对规范路径；路径不存在返回 nil）
    private static func realpath(_ path: String) -> String? {
        guard let c = Foundation.realpath(path, nil) else { return nil }
        defer { free(c) }
        return String(cString: c)
    }
}
