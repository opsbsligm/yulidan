import Foundation
import SwiftUI
import Workspace

/// 工作区路由（P0.1.5 起；2026-08-30 起纯本地单根：SSO/iCloud 模块整体移除）
/// - 本地根 = ~/Library/Application Support/Harness（agents/rag/plugins-meta/themes/memory 标准骨架）
/// 目录契约来自 Workspace.WorkspaceLayout（业务侧按名引用子目录）。
@MainActor
public final class WorkspaceRouter: ObservableObject {
    @Published public private(set) var current: WorkspaceRoot

    private let provider: WorkspaceRootProvider

    public init(provider: WorkspaceRootProvider? = nil) {
        self.provider = provider ?? WorkspaceRootProvider()
        current = self.provider.resolveLocal()
        materialize()
    }

    // MARK: - 运行时目录（本地根）

    /// Agent 产出文件根
    public var agentOutputs: URL {
        current.url(for: WorkspaceLayout.agentOutputs)
    }

    /// RAG 向量库索引
    public var ragIndexURL: URL {
        current.url(for: WorkspaceLayout.ragStore).appendingPathComponent("index.json")
    }

    /// 插件元数据清单（MCP 二进制不落工作区，仅元数据/启用状态/配置 — P0.4.4）
    public var pluginMetaURL: URL {
        current.url(for: WorkspaceLayout.pluginMeta).appendingPathComponent("installed.json")
    }

    /// 主题插件资源（文件型主题包 spec.json — P0.4.3 社区主题包兼容）
    public var themeResources: URL {
        current.url(for: WorkspaceLayout.themeResources)
    }

    /// 长期记忆库（契约 v2：本地根 memory/longterm.json）
    public var memoryStoreURL: URL {
        current.url(for: WorkspaceLayout.memoryStore).appendingPathComponent("longterm.json")
    }

    /// 每会话 Agent 工作目录（会话创建时落定）
    public func sessionCwd(_ sessionID: UUID) -> URL {
        agentOutputs.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    // MARK: - 物化

    /// 物化标准目录骨架（幂等；失败静默）
    public func materialize() {
        let fm = FileManager.default
        for directory in WorkspaceLayout.allDirectories {
            try? fm.createDirectory(at: current.url(for: directory), withIntermediateDirectories: true)
        }
    }
}
