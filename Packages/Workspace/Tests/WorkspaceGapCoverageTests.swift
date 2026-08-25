import Foundation
import Testing
@testable import Workspace

// MARK: - Workspace 包薄弱分支覆盖（覆盖审计轮 15）

@Suite("Workspace Gap Coverage")
struct WorkspaceGapCoverageTests {
    /// ProjectID.description：UUID 包装 → uuidString（CustomStringConvertible 分支）
    @Test("ProjectID.description = uuidString")
    func projectIDDescription() {
        let uuid = UUID()
        let id = ProjectID(uuid)
        #expect(id.description == uuid.uuidString)
        // 默认 init：rawValue 随机，description 与 rawValue 恒一致
        let id2 = ProjectID()
        #expect(id2.description == id2.rawValue.uuidString)
    }

    /// SidebarModel.ProjectSection.id：透传所属项目 id（分区 Identifiable 身份源）
    @Test("ProjectSection.id 透传所属项目 id")
    func projectSectionID() {
        let project = Project(name: "P1")
        let section = SidebarModel.ProjectSection(project: project, sessions: [])
        #expect(section.id == project.id)
    }

    /// Project(row:)：持久化行映射往返（GRDB 层加载路径；id 非法 UUID 时回退随机 UUID 不崩溃）
    @Test("Project(row:) 往返一致")
    func projectRowRoundTrip() {
        let project = Project(name: "P1", archived: true, collapsed: true, sortOrder: 3)
        let back = Project(row: project.row)
        #expect(back.id == project.id)
        #expect(back.name == project.name)
        #expect(back.createdAt == project.createdAt)
        #expect(back.archived == project.archived)
        #expect(back.collapsed == project.collapsed)
        #expect(back.sortOrder == project.sortOrder)
    }

    /// WorkspaceSyncPayload.encode/decode：KVS 单 blob 编解码往返
    @Test("WorkspaceSyncPayload encode/decode 往返一致")
    func syncPayloadEncodeDecode() {
        let payload = WorkspaceSyncPayload(
            projects: [Project(name: "P1")],
            sessionAssignments: ["k": SessionAssignment(projectId: nil, archived: false)]
        )
        let data = WorkspaceSyncPayload.encode(payload)
        #expect(WorkspaceSyncPayload.decode(data) == payload)
    }
}
