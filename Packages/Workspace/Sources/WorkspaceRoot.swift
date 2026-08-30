import Foundation

/// 工作区种类（2026-08-30 起 App 为纯本地模式：SSO/iCloud 模块整体移除，仅保留 local 根）
public enum WorkspaceKind: String, Codable, Sendable {
    case local
}

/// 目录契约：本地根标准布局，业务侧按名引用子目录
public enum WorkspaceLayout {
    /// Agent 产出文件
    public static let agentOutputs = "agents"
    /// RAG 向量库
    public static let ragStore = "rag"
    /// 插件元数据（MCP 二进制不落工作区）
    public static let pluginMeta = "plugins-meta"
    /// 主题插件资源
    public static let themeResources = "themes"
    /// 长期记忆库（契约 v2：记忆随工作区根，本地单根）
    public static let memoryStore = "memory"

    public static let allDirectories: [String] = [agentOutputs, ragStore, pluginMeta, themeResources, memoryStore]
}

public struct WorkspaceRoot: Equatable, Sendable {
    public let kind: WorkspaceKind
    public let rootURL: URL

    public init(kind: WorkspaceKind, rootURL: URL) {
        self.kind = kind
        self.rootURL = rootURL
    }

    public func url(for directory: String) -> URL {
        rootURL.appendingPathComponent(directory, isDirectory: true)
    }
}

/// 本地工作区根解析器（纯逻辑 + 可注入根目录；单测用临时目录隔离）
public struct WorkspaceRootProvider: Sendable {
    public let localRoot: URL

    public init(localRoot: URL? = nil) {
        if let localRoot {
            self.localRoot = localRoot
        } else {
            self.localRoot = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Harness", isDirectory: true)
        }
    }

    /// 本地根（唯一可用根）
    public func resolveLocal() -> WorkspaceRoot {
        WorkspaceRoot(kind: .local, rootURL: localRoot)
    }

    /// 物化标准目录骨架（幂等）
    @discardableResult
    public func materialize(_ root: WorkspaceRoot) throws -> [URL] {
        let fm = FileManager.default
        return try WorkspaceLayout.allDirectories.map { directory in
            let url = root.url(for: directory)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }
}
