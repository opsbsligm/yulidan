import Foundation
import Session

/// 会话归属/归档的同步条目（key = 会话 UUID 字符串）
public struct SessionAssignment: Codable, Equatable, Sendable {
    public var projectId: UUID?
    public var archived: Bool

    public init(projectId: UUID? = nil, archived: Bool = false) {
        self.projectId = projectId
        self.archived = archived
    }
}

/// 工作区元数据同步载荷（KVS 单 blob，LWW + 冲突用户裁决）。
/// 覆盖：项目实体（名称/归档/折叠/排序）+ 会话项目归属 + 会话归档态。
/// 会话内容/事件不在本载荷（由工作区文件与 DB 各自负责，MVP 阶段仅同步元数据）。
public struct WorkspaceSyncPayload: Codable, Equatable, Sendable {
    public static let version = 1
    /// KVS key
    public static let kvsKey = "workspace.v1"

    public let version: Int
    public var projects: [Project]
    /// 键 = 会话 UUID 字符串
    public var sessionAssignments: [String: SessionAssignment]

    public init(
        version: Int = Self.version,
        projects: [Project],
        sessionAssignments: [String: SessionAssignment] = [:]
    ) {
        self.version = version
        self.projects = projects
        self.sessionAssignments = sessionAssignments
    }

    // MARK: - 编解码

    public static func encode(_ payload: WorkspaceSyncPayload) -> Data {
        (try? JSONEncoder().encode(payload)) ?? Data()
    }

    public static func decode(_ data: Data) -> WorkspaceSyncPayload? {
        try? JSONDecoder().decode(WorkspaceSyncPayload.self, from: data)
    }

    /// 从当前本地状态构建载荷（发布用）
    public static func build(
        projects: [Project],
        sessions: [SessionRecord]
    ) -> WorkspaceSyncPayload {
        var assignments: [String: SessionAssignment] = [:]
        for session in sessions {
            let key = session.id.rawValue.uuidString
            assignments[key] = SessionAssignment(
                projectId: session.metadata.projectId,
                archived: session.metadata.archived
            )
        }
        return WorkspaceSyncPayload(projects: projects, sessionAssignments: assignments)
    }

    // MARK: - 应用（冲突胜者/首次同步）

    /// 单条会话归属变更
    public struct SessionChange: Equatable, Sendable {
        public let sessionId: UUID
        public var projectId: UUID?
        public var archived: Bool

        public init(sessionId: UUID, projectId: UUID?, archived: Bool) {
            self.sessionId = sessionId
            self.projectId = projectId
            self.archived = archived
        }
    }

    /// 将胜出载荷应用到当前状态所产生的变更清单（纯函数；由持久层执行）。
    /// - 项目：仅收录与本地状态存在差异的（upsert）；本地存在而载荷缺失 → 删除（LWW 语义）
    /// - 会话：仅对本地已知会话（assignment 键存在）应用远端归属/归档差异
    public static func applyChanges(
        currentProjects: [Project],
        currentAssignments: [String: SessionAssignment],
        payload: WorkspaceSyncPayload
    ) -> WorkspaceChangeSet {
        var set = WorkspaceChangeSet()
        let currentByID = Dictionary(uniqueKeysWithValues: currentProjects.map { ($0.id, $0) })
        set.projectsToSave = payload.projects.filter { remote in
            guard let current = currentByID[remote.id] else { return true }
            return current.name != remote.name
                || current.archived != remote.archived
                || current.collapsed != remote.collapsed
                || current.sortOrder != remote.sortOrder
        }
        set.projectIDsToRemove = currentProjects
            .filter { !Set(payload.projects.map(\.id)).contains($0.id) }
            .map(\.id)
        for (key, current) in currentAssignments {
            guard let remote = payload.sessionAssignments[key],
                  let sessionID = UUID(uuidString: key) else { continue }
            if remote.projectId != current.projectId || remote.archived != current.archived {
                set.sessionChanges[sessionID] = SessionChange(
                    sessionId: sessionID,
                    projectId: remote.projectId,
                    archived: remote.archived
                )
            }
        }
        return set
    }
}

/// 工作区同步变更集（持久层执行单位）
public struct WorkspaceChangeSet: Equatable, Sendable {
    public var projectsToSave: [Project] = []
    public var projectIDsToRemove: [ProjectID] = []
    public var sessionChanges: [UUID: WorkspaceSyncPayload.SessionChange] = [:]

    public init() {}

    public var isEmpty: Bool {
        projectsToSave.isEmpty && projectIDsToRemove.isEmpty && sessionChanges.isEmpty
    }
}
