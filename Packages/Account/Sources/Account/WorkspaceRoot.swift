import Foundation

/// 工作区种类（双根严格隔离，数据互不污染）
public enum WorkspaceKind: String, Codable, Sendable {
    case local
    case icloud
}

/// 目录契约：两套根同构布局，业务侧按名引用子目录
public enum WorkspaceLayout {
    /// Agent 产出文件
    public static let agentOutputs = "agents"
    /// RAG 向量库
    public static let ragStore = "rag"
    /// 插件元数据（MCP 二进制不同步，仅元数据）
    public static let pluginMeta = "plugins-meta"
    /// 主题插件资源
    public static let themeResources = "themes"
    /// 同步暂存（离线队列等）
    public static let syncStaging = "sync"

    public static let allDirectories: [String] = [agentOutputs, ragStore, pluginMeta, themeResources, syncStaging]
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

/// iCloud 容器标识约定：iCloud.<bundle id>
public enum ContainerIdentifier {
    public static let defaultID = "iCloud.com.deepseek.harness"
}

/// 双根解析器（纯逻辑 + 可注入探测；单测用临时目录隔离）
public struct WorkspaceRootProvider: Sendable {
    public let containerIdentifier: String
    public let localRoot: URL
    private let probe: any UbiquityProbing

    public init(
        containerIdentifier: String = ContainerIdentifier.defaultID,
        localRoot: URL? = nil,
        probe: any UbiquityProbing = DefaultUbiquityProbe()
    ) {
        self.containerIdentifier = containerIdentifier
        if let localRoot {
            self.localRoot = localRoot
        } else {
            self.localRoot = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Harness", isDirectory: true)
        }
        self.probe = probe
    }

    /// 本地根（始终可用）
    public func resolveLocal() -> WorkspaceRoot {
        WorkspaceRoot(kind: .local, rootURL: localRoot)
    }

    /// iCloud 根（nil = 容器不可用）
    public func resolveICloud() -> WorkspaceRoot? {
        let p = probe.probe(containerIdentifier: containerIdentifier)
        guard let container = p.containerURL else { return nil }
        return WorkspaceRoot(kind: .icloud, rootURL: container.appendingPathComponent("Documents", isDirectory: true))
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
