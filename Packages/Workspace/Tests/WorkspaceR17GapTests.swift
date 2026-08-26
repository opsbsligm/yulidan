import Foundation
import Session
import Testing
import Workspace

// MARK: - 覆盖审计轮 17：Workspace 残余兜底行（Project row UUID 兜底 / SidebarModelBuilder 排序闭包）

@Suite("Workspace R17 Gap Coverage")
struct WorkspaceR17GapTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(_ id: String, created: TimeInterval, project: UUID? = nil,
                         archived: Bool = false) -> SessionRecord {
        SessionRecord(
            id: SessionID(rawValue: UUID(uuidString: id)!),
            metadata: SessionMetadata(
                cwd: URL(fileURLWithPath: "/tmp"),
                createdAt: baseDate.addingTimeInterval(created),
                projectId: project,
                archived: archived
            )
        )
    }

    /// ① 脏行 id 非法 → `UUID(uuidString:) ?? UUID()` 兜底
    @Test("Project: 脏行 id → UUID 兜底")
    func projectRowBadUUID() {
        let row = ProjectRow(id: "not-a-uuid", name: "坏行项目", createdAt: baseDate,
                             archived: false, collapsed: false, sortOrder: 0)
        let project = Project(row: row)
        #expect(project.name == "坏行项目")
        // 兜底生成随机 UUID（仅验证非崩溃且字段保真）
        #expect(project.sortOrder == 0)
        #expect(!project.archived)
    }

    /// ② 多项目 + 多会话 → build 内部分区过滤 / createdAt 倒序排序闭包全部执行
    @Test("SidebarModelBuilder: 多项目多会话排序闭包")
    func sidebarBuildSortClosures() throws {
        let p1 = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let p2 = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let p3 = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let p4 = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

        let projects: [Project] = [
            // 活跃项目 sortOrder 乱序 → ordered 排序闭包
            Project(id: ProjectID(p1), name: "项目一", sortOrder: 2),
            Project(id: ProjectID(p2), name: "项目二", sortOrder: 1),
            // 归档项目两条乱序 → 归档分区排序闭包
            Project(id: ProjectID(p3), name: "归档甲", archived: true, sortOrder: 2),
            Project(id: ProjectID(p4), name: "归档乙", archived: true, sortOrder: 1),
        ]
        let sessions: [SessionRecord] = [
            // 项目一内两条（createdAt 乱序）
            session("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", created: 10, project: p1),
            session("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", created: 30, project: p1),
            // 全局两条（createdAt 乱序）
            session("cccccccc-cccc-cccc-cccc-cccccccccccc", created: 5),
            session("dddddddd-dddd-dddd-dddd-dddddddddddd", created: 20),
            // 归档会话两条（createdAt 乱序 → 归档会话排序闭包执行）
            session("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", created: 1, archived: true),
            session("ffffffff-ffff-ffff-ffff-ffffffffffff", created: 8, archived: true),
        ]

        let model = SidebarModelBuilder.build(projects: projects, sessions: sessions)

        // 活跃分区按 sortOrder 升序：项目二在前
        #expect(model.projectSections.map(\.project.name) == ["项目二", "项目一"])
        // 项目一会话 createdAt 倒序
        #expect(model.projectSections.first { $0.project.id.rawValue == p1 }?.sessions.count == 2)
        // 全局会话 createdAt 倒序
        #expect(model.globalSessions.count == 2)
        #expect(try #require(model.globalSessions.first?.metadata.createdAt) > model.globalSessions.last!.metadata.createdAt)
        // 归档项目 sortOrder 升序
        #expect(model.archivedProjects.map(\.name) == ["归档乙", "归档甲"])
        // 归档会话（createdAt 倒序）
        #expect(model.archivedSessions.count == 2)
        #expect(try #require(model.archivedSessions.first?.metadata.createdAt) > model.archivedSessions.last!.metadata.createdAt)
    }
}
