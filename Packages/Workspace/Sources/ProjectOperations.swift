import Foundation
import Session

// MARK: - 删除项目（二选一策略）

/// 删除项目策略（UI 二选一）
public enum DeleteProjectOption: String, Sendable, Codable, CaseIterable {
    /// 删除项目及其内部全部会话
    case deleteAllSessions
    /// 保留会话，释放至全局顶层列表
    case releaseToGlobal
}

/// 删除计划（纯计算，UI 确认后由持久层执行）
public struct ProjectDeletionPlan: Equatable, Sendable {
    public let projectID: ProjectID
    public let option: DeleteProjectOption
    /// 受影响的会话 ID（deleteAllSessions = 待删除；releaseToGlobal = 待改归属）
    public let affectedSessionIDs: Set<UUID>

    public init(projectID: ProjectID, option: DeleteProjectOption, affectedSessionIDs: Set<UUID>) {
        self.projectID = projectID
        self.option = option
        self.affectedSessionIDs = affectedSessionIDs
    }
}

// MARK: - 会话移动（拖拽解析）

/// 拖拽目标
public enum SessionDropTarget: Equatable, Sendable {
    /// 移入/迁移到指定项目
    case project(ProjectID)
    /// 拖回全局顶层
    case global
}

/// 拖拽放置解析结果
public enum SessionMoveResolution: Equatable, Sendable {
    /// 归属无变化（同项目内拖拽）
    case noChange
    /// 需要写入的新 projectId（nil = 全局；与 SessionMetadata.projectId 裸 UUID 对齐）
    case assign(UUID?)
}

/// 项目与会话归属的纯逻辑操作
public enum ProjectOperations {
    /// 生成删除计划
    public static func planDeletion(
        project: Project,
        sessions: [SessionRecord],
        option: DeleteProjectOption
    ) -> ProjectDeletionPlan {
        let affected = Set(
            sessions
                .filter { $0.metadata.projectId == project.id.rawValue }
                .map(\.id.rawValue)
        )
        return ProjectDeletionPlan(projectID: project.id, option: option, affectedSessionIDs: affected)
    }

    /// 解析拖拽放置：当前归属 → 目标归属（同项目 = noChange）
    public static func resolveMove(
        session: SessionRecord,
        target: SessionDropTarget
    ) -> SessionMoveResolution {
        let from = session.metadata.projectId
        switch target {
        case let .project(pid):
            if from == pid.rawValue {
                return .noChange
            }
            return .assign(pid.rawValue)
        case .global:
            if from == nil {
                return .noChange
            }
            return .assign(nil)
        }
    }

    /// 取消归档时的项目回落：原项目仍存在且未归档 → 恢复原项目；已删除/已归档 → 全局
    public static func resolveRestoreProject(
        session: SessionRecord,
        projects: [Project]
    ) -> ProjectID? {
        guard let pid = session.metadata.projectId else { return nil }
        guard let project = projects.first(where: { $0.id.rawValue == pid }) else { return nil }
        guard !project.archived else { return nil }
        return project.id
    }

    /// 手动重排项目（拖拽排序）：moving 移到 before 之前；before nil = 移到尾部。
    /// 输入数组按当前展示序（sortOrder 升序）传入；返回重排后的完整数组（sortOrder 按索引归一）。
    public static func reorder(
        projects: [Project],
        moving id: ProjectID,
        before target: ProjectID?
    ) -> [Project] {
        guard let fromIndex = projects.firstIndex(where: { $0.id == id }) else { return projects }
        var ordered = projects
        let moved = ordered.remove(at: fromIndex)
        let insertIndex: Int = if let target, let toIndex = ordered.firstIndex(where: { $0.id == target }) {
            toIndex
        } else {
            ordered.count
        }
        ordered.insert(moved, at: insertIndex)
        return ordered.enumerated().map { index, project in
            project.withSortOrder(Double(index))
        }
    }

    /// 新项目的 sortOrder（追加尾部 = 当前最大值 + 1）
    public static func nextSortOrder(after projects: [Project]) -> Double {
        (projects.map(\.sortOrder).max() ?? -1) + 1
    }

    /// 按展示序排序（sortOrder 升序，平手按创建时间升序）
    public static func ordered(_ projects: [Project]) -> [Project] {
        projects.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
