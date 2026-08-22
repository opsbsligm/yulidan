import Account
import Foundation
import SwiftUI

/// 工作区路由（P0.1.5）：按 AccountService 当前模式路由 App 运行时目录集
/// - 本地模式 → 本地根（~/Library/Application Support/Harness）
/// - iCloud 模式 → iCloud Documents 容器根（agents/rag/plugins-meta/themes/sync 标准骨架）
/// 双根同构、严格隔离：数据互不污染、不自动迁移（目标「两套存储严格隔离」口径）。
/// 目录契约来自 Account.WorkspaceLayout（两套根同构，业务侧按名引用子目录）。
@MainActor
public final class WorkspaceRouter: ObservableObject {
    @Published public private(set) var current: WorkspaceRoot

    private let accountService: AccountService

    public init(accountService: AccountService) {
        self.accountService = accountService
        current = accountService.currentWorkspace
        materialize()
    }

    // MARK: - 运行时目录（随模式路由）

    /// Agent 产出文件根（iCloud 模式 = 容器/agents）
    public var agentOutputs: URL {
        current.url(for: WorkspaceLayout.agentOutputs)
    }

    /// RAG 向量库索引（iCloud 模式 = 容器/rag/index.json）
    public var ragIndexURL: URL {
        current.url(for: WorkspaceLayout.ragStore).appendingPathComponent("index.json")
    }

    /// 插件元数据清单（MCP 二进制不同步，仅元数据/启用状态/配置 — P0.4.4）
    public var pluginMetaURL: URL {
        current.url(for: WorkspaceLayout.pluginMeta).appendingPathComponent("installed.json")
    }

    /// 主题插件资源（文件型主题包 spec.json — P0.4.3 社区主题包兼容）
    public var themeResources: URL {
        current.url(for: WorkspaceLayout.themeResources)
    }

    /// 长期记忆库（契约 v2：iCloud 模式 = 容器/memory/longterm.json，双根严格隔离）
    public var memoryStoreURL: URL {
        current.url(for: WorkspaceLayout.memoryStore).appendingPathComponent("longterm.json")
    }

    /// 每会话 Agent 工作目录（会话创建时落定；切模式不影响既有会话）
    public func sessionCwd(_ sessionID: UUID) -> URL {
        agentOutputs.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    public var isICloud: Bool {
        current.kind == .icloud
    }

    // MARK: - 模式切换

    /// 账号状态变化后重算路由（AppViewModel 在 objectWillChange 观察中调用）。
    /// 返回 true = 根发生变化（调用方需重路由运行时目录）。
    @discardableResult
    public func refresh() -> Bool {
        let next = accountService.currentWorkspace
        guard next != current else { return false }
        current = next
        materialize()
        return true
    }

    /// 物化标准目录骨架（幂等；失败静默 — 容器未就绪时由 AccountService 降级逻辑兜底）
    public func materialize() {
        let fm = FileManager.default
        for directory in WorkspaceLayout.allDirectories {
            try? fm.createDirectory(at: current.url(for: directory), withIntermediateDirectories: true)
        }
    }
}
