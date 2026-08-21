import Foundation
import Session

/// 项目 ID（UUID 包装；与 SessionMetadata.projectId 裸 UUID 互转）
public struct ProjectID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(_ uuid: UUID) {
        rawValue = uuid
    }

    public var description: String {
        rawValue.uuidString
    }
}

/// 项目 — Codex 式侧边栏项目模型（无上限新建）
/// 持久化行映射：Session.ProjectRow（Session 包，GRDB 层）
public struct Project: Identifiable, Hashable, Codable, Sendable {
    public let id: ProjectID
    public var name: String
    public var createdAt: Date
    /// 归档（不在主侧边栏显示；归档管理入口查看/取消归档）
    public var archived: Bool
    /// 折叠（展开/收起分组，持久化）
    public var collapsed: Bool
    /// 排序权重（手动重排后按索引归一；新建追加尾部）
    public var sortOrder: Double

    public init(
        id: ProjectID = ProjectID(),
        name: String,
        createdAt: Date = Date(),
        archived: Bool = false,
        collapsed: Bool = false,
        sortOrder: Double = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.archived = archived
        self.collapsed = collapsed
        self.sortOrder = sortOrder
    }

    // MARK: - 副本变换

    public func renamedTo(_ name: String) -> Project {
        var copy = self
        copy.name = name
        return copy
    }

    public func withArchived(_ archived: Bool) -> Project {
        var copy = self
        copy.archived = archived
        return copy
    }

    public func withCollapsed(_ collapsed: Bool) -> Project {
        var copy = self
        copy.collapsed = collapsed
        return copy
    }

    public func withSortOrder(_ sortOrder: Double) -> Project {
        var copy = self
        copy.sortOrder = sortOrder
        return copy
    }

    // MARK: - 持久化行映射

    public var row: ProjectRow {
        ProjectRow(
            id: id.rawValue.uuidString,
            name: name,
            createdAt: createdAt,
            archived: archived,
            collapsed: collapsed,
            sortOrder: sortOrder
        )
    }

    public init(row: ProjectRow) {
        id = ProjectID(UUID(uuidString: row.id) ?? UUID())
        name = row.name
        createdAt = row.createdAt
        archived = row.archived
        collapsed = row.collapsed
        sortOrder = row.sortOrder
    }
}
