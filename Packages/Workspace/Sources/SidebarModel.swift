import Foundation
import Session

/// 侧边栏分区模型（纯函数产物；UI 层只做渲染）
public struct SidebarModel: Equatable, Sendable {
    public struct ProjectSection: Identifiable, Equatable, Sendable {
        public let project: Project
        /// 项目内未归档会话（createdAt 倒序）
        public let sessions: [SessionRecord]
        public var id: ProjectID {
            project.id
        }
    }

    /// 活跃项目分区（未归档，展示序：sortOrder 升序）
    public let projectSections: [ProjectSection]
    /// 全局顶层会话（无项目归属 + 未归档；createdAt 倒序）
    public let globalSessions: [SessionRecord]
    /// 归档项目（归档管理入口展示）
    public let archivedProjects: [Project]
    /// 归档会话（归档管理入口展示；createdAt 倒序）
    public let archivedSessions: [SessionRecord]

    public init(
        projectSections: [ProjectSection],
        globalSessions: [SessionRecord],
        archivedProjects: [Project],
        archivedSessions: [SessionRecord]
    ) {
        self.projectSections = projectSections
        self.globalSessions = globalSessions
        self.archivedProjects = archivedProjects
        self.archivedSessions = archivedSessions
    }
}

/// 侧边栏分区构建（纯逻辑，可测）
public enum SidebarModelBuilder {
    /// 从项目与会话列表构建侧边栏模型（归档项从主区剔除，集中供归档管理入口）
    public static func build(
        projects: [Project],
        sessions: [SessionRecord]
    ) -> SidebarModel {
        let activeProjects = ProjectOperations.ordered(projects.filter { !$0.archived })
        let sections = activeProjects.map { project in
            let pid = project.id.rawValue
            let items = sessions
                .filter { !$0.metadata.archived && $0.metadata.projectId == pid }
                .sorted { $0.metadata.createdAt > $1.metadata.createdAt }
            return SidebarModel.ProjectSection(project: project, sessions: items)
        }
        let global = sessions
            .filter { !$0.metadata.archived && $0.metadata.projectId == nil }
            .sorted { $0.metadata.createdAt > $1.metadata.createdAt }
        let archivedProjects = ProjectOperations.ordered(projects.filter(\.archived))
        let archivedSessions = sessions
            .filter(\.metadata.archived)
            .sorted { $0.metadata.createdAt > $1.metadata.createdAt }
        return SidebarModel(
            projectSections: sections,
            globalSessions: global,
            archivedProjects: archivedProjects,
            archivedSessions: archivedSessions
        )
    }

    /// 会话当前所属项目（含已归档项目判定）
    public static func project(for session: SessionRecord, in projects: [Project]) -> Project? {
        guard let pid = session.metadata.projectId else { return nil }
        return projects.first { $0.id.rawValue == pid }
    }
}
