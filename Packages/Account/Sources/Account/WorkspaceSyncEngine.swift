import Foundation
import Workspace

/// 工作区状态存储抽象（同步引擎与具体持久层解耦）。
/// async throws：生产实现基于 SessionDB（actor）；同步 fake 可直接见证 async 需求。
public protocol WorkspaceStateStoring: Sendable {
    /// 全部项目（含归档，展示序由持久层保证）
    func loadProjects() async throws -> [Project]
    /// 会话归属/归档投影（key = 会话 UUID 字符串，与同步载荷键空间一致）
    func loadSessionAssignments() async throws -> [String: SessionAssignment]
    /// 应用同步变更集（upsert 项目 / 删项目 / 改会话归属归档）
    func apply(_ changes: WorkspaceChangeSet) async throws
}

/// 工作区元数据同步引擎。
/// 职责：
/// - publishLocalState：本地状态 → 载荷 → KVS 发布（本地变更后调用）
/// - applyRemoteValue：远端值 → 解码 → 与本地求差 → 变更集落库
/// 失败策略：解码失败 / 读本地失败 / 落库失败均静默吞掉（离线优先：
/// 本地状态绝不被坏数据污染，等待下一轮外部变更或用户操作重试）。
public actor WorkspaceSyncEngine {
    private let sync: MetadataSyncService
    private let store: any WorkspaceStateStoring

    public init(sync: MetadataSyncService, store: any WorkspaceStateStoring) {
        self.sync = sync
        self.store = store
    }

    /// 本地变更后发布全量工作区载荷（LWW 单 blob）
    public func publishLocalState() async {
        do {
            let projects = try await store.loadProjects()
            let assignments = try await store.loadSessionAssignments()
            let payload = WorkspaceSyncPayload(projects: projects, sessionAssignments: assignments)
            let data = WorkspaceSyncPayload.encode(payload)
            guard !data.isEmpty else { return }
            await sync.publish(key: WorkspaceSyncPayload.kvsKey, value: data)
        } catch {
            // 本地读失败不中断主流程；下一次本地变更发布时自动重试
        }
    }

    /// 应用远端工作区值（外部 KVS 变更 / attach 时初始值）
    public func applyRemoteValue(_ data: Data) async {
        guard let payload = WorkspaceSyncPayload.decode(data) else { return }
        do {
            let currentProjects = try await store.loadProjects()
            let currentAssignments = try await store.loadSessionAssignments()
            let changes = WorkspaceSyncPayload.applyChanges(
                currentProjects: currentProjects,
                currentAssignments: currentAssignments,
                payload: payload
            )
            guard !changes.isEmpty else { return }
            try await store.apply(changes)
        } catch {
            // 静默：等待下一轮外部变更
        }
    }
}
