import Foundation
import Session
import Testing
@testable import Workspace

// MARK: - 测试夹具

/// 构造带项目归属/归档态的会话
enum WorkspaceTestFixtures {
    static func makeSession(
        _ id: UUID,
        name: String = "会话",
        projectId: UUID? = nil,
        archived: Bool = false,
        createdAt: Date = Date()
    ) -> SessionRecord {
        let meta = SessionMetadata(
            cwd: URL(fileURLWithPath: "/tmp"),
            createdAt: createdAt,
            projectId: projectId,
            archived: archived
        )
        var record = SessionRecord(id: SessionID(rawValue: id), metadata: meta)
        record.append(.userMessage(UserMessage(content: [.text(name)])))
        return record
    }

    static func makeProject(
        _ name: String,
        id: ProjectID? = nil,
        archived: Bool = false,
        collapsed: Bool = false,
        sortOrder: Double = 0
    ) -> Project {
        Project(id: id ?? ProjectID(), name: name, archived: archived,
                collapsed: collapsed, sortOrder: sortOrder)
    }
}

// MARK: - 删除项目二选一

@Suite("删除项目二选一策略")
struct DeleteProjectTests {
    let pid = UUID()
    let otherPid = UUID()
    let s1 = UUID(), s2 = UUID(), s3 = UUID(), s4 = UUID()

    private var sessions: [SessionRecord] {
        [
            WorkspaceTestFixtures.makeSession(s1, projectId: pid),
            WorkspaceTestFixtures.makeSession(s2, projectId: pid),
            WorkspaceTestFixtures.makeSession(s3, projectId: otherPid),
            WorkspaceTestFixtures.makeSession(s4),
        ]
    }

    @Test("deleteAllSessions 仅收集本项目会话")
    func deleteAllSessions() {
        let plan = ProjectOperations.planDeletion(
            project: WorkspaceTestFixtures.makeProject("P1", id: ProjectID(pid)),
            sessions: sessions, option: .deleteAllSessions
        )
        #expect(plan.option == .deleteAllSessions)
        #expect(plan.affectedSessionIDs == Set([s1, s2]))
    }

    @Test("releaseToGlobal 同样收集本项目会话（执行语义不同）")
    func releaseToGlobal() {
        let plan = ProjectOperations.planDeletion(
            project: WorkspaceTestFixtures.makeProject("P1", id: ProjectID(pid)),
            sessions: sessions, option: .releaseToGlobal
        )
        #expect(plan.option == .releaseToGlobal)
        #expect(plan.affectedSessionIDs == Set([s1, s2]))
    }

    @Test("空项目 affected 为空集")
    func emptyProject() {
        let plan = ProjectOperations.planDeletion(
            project: WorkspaceTestFixtures.makeProject("空", id: ProjectID(UUID())),
            sessions: sessions, option: .deleteAllSessions
        )
        #expect(plan.affectedSessionIDs.isEmpty)
    }
}

// MARK: - 拖拽放置解析

@Suite("拖拽放置解析")
struct MoveResolutionTests {
    let g = UUID() // 会话
    let pa = UUID() // 项目 A
    let pb = UUID()

    @Test("全局拖入项目 = assign(project)")
    func globalToProject() {
        let r = ProjectOperations.resolveMove(
            session: WorkspaceTestFixtures.makeSession(g),
            target: .project(ProjectID(pa))
        )
        #expect(r == .assign(pa))
    }

    @Test("项目内拖回全局 = assign(nil)")
    func projectToGlobal() {
        let r = ProjectOperations.resolveMove(
            session: WorkspaceTestFixtures.makeSession(g, projectId: pa),
            target: .global
        )
        #expect(r == .assign(nil))
    }

    @Test("A 项目迁移至 B 项目 = assign(B)")
    func crossProject() {
        let r = ProjectOperations.resolveMove(
            session: WorkspaceTestFixtures.makeSession(g, projectId: pa),
            target: .project(ProjectID(pb))
        )
        #expect(r == .assign(pb))
    }

    @Test("同项目拖拽 / 全局拖回全局 = noChange")
    func noChange() {
        #expect(ProjectOperations.resolveMove(
            session: WorkspaceTestFixtures.makeSession(g, projectId: pa),
            target: .project(ProjectID(pa))
        ) == .noChange)
        #expect(ProjectOperations.resolveMove(
            session: WorkspaceTestFixtures.makeSession(g),
            target: .global
        ) == .noChange)
    }

    @Test("Transferable 载荷编解码往返 + resolution 与纯函数一致")
    func dragPayloadRoundTrip() throws {
        let payload = SessionDragPayload(sessionID: g, fromProjectID: pa)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SessionDragPayload.self, from: data)
        #expect(decoded == payload)
        #expect(decoded.resolution(target: .project(ProjectID(pb))) == .assign(pb))
        #expect(decoded.resolution(target: .project(ProjectID(pa))) == .noChange)
        #expect(decoded.resolution(target: .global) == .assign(nil))
    }
}

// MARK: - 取消归档回落

@Suite("取消归档项目回落")
struct RestoreProjectTests {
    @Test("原项目存在且未归档 → 恢复原项目")
    func restoreActive() {
        let pid = UUID()
        let session = WorkspaceTestFixtures.makeSession(UUID(), projectId: pid, archived: true)
        let projects = [WorkspaceTestFixtures.makeProject("P", id: ProjectID(pid))]
        #expect(ProjectOperations.resolveRestoreProject(session: session, projects: projects) == ProjectID(pid))
    }

    @Test("原项目已归档 → 回落全局")
    func restoreArchivedFallsBack() {
        let pid = UUID()
        let session = WorkspaceTestFixtures.makeSession(UUID(), projectId: pid, archived: true)
        let projects = [WorkspaceTestFixtures.makeProject("P", id: ProjectID(pid), archived: true)]
        #expect(ProjectOperations.resolveRestoreProject(session: session, projects: projects) == nil)
    }

    @Test("原项目已删除 → 回落全局")
    func restoreDeletedFallsBack() {
        let session = WorkspaceTestFixtures.makeSession(UUID(), projectId: UUID(), archived: true)
        #expect(ProjectOperations.resolveRestoreProject(session: session, projects: []) == nil)
    }

    @Test("无归属会话 → nil")
    func noProject() {
        let session = WorkspaceTestFixtures.makeSession(UUID(), archived: true)
        #expect(ProjectOperations.resolveRestoreProject(session: session, projects: [
            WorkspaceTestFixtures.makeProject("P"),
        ]) == nil)
    }
}

// MARK: - 手动重排 / 新建排序

@Suite("项目排序")
struct ReorderTests {
    private func proj(_ name: String, order: Double) -> Project {
        WorkspaceTestFixtures.makeProject(name, sortOrder: order)
    }

    @Test("移到中部")
    func moveMiddle() {
        let a = proj("a", order: 0), b = proj("b", order: 1), c = proj("c", order: 2), d = proj("d", order: 3)
        let out = ProjectOperations.reorder(projects: [a, b, c, d], moving: a.id, before: c.id)
        #expect(out.map(\.name) == ["b", "a", "c", "d"])
        #expect(out.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("移到尾部")
    func moveTail() {
        let a = proj("a", order: 0), b = proj("b", order: 1), c = proj("c", order: 2)
        let out = ProjectOperations.reorder(projects: [a, b, c], moving: a.id, before: nil)
        #expect(out.map(\.name) == ["b", "c", "a"])
    }

    @Test("移到头部")
    func moveHead() {
        let a = proj("a", order: 0), b = proj("b", order: 1)
        let out = ProjectOperations.reorder(projects: [a, b], moving: b.id, before: a.id)
        #expect(out.map(\.name) == ["b", "a"])
    }

    @Test("未知 id 原样返回")
    func unknownID() {
        let a = proj("a", order: 0)
        let out = ProjectOperations.reorder(projects: [a], moving: ProjectID(), before: nil)
        #expect(out == [a])
    }

    @Test("nextSortOrder 追加尾部")
    func nextOrder() {
        #expect(ProjectOperations.nextSortOrder(after: []) == 0)
        #expect(ProjectOperations.nextSortOrder(after: [proj("a", order: 5)]) == 6)
    }

    @Test("ordered 按 sortOrder 升序、平手按创建时间")
    func ordered() {
        let p1 = Project(name: "x", createdAt: .distantPast, sortOrder: 1)
        let p0 = Project(name: "y", createdAt: .distantFuture, sortOrder: 1)
        let p2 = Project(name: "z", sortOrder: 0)
        let out = ProjectOperations.ordered([p1, p0, p2])
        #expect(out.map(\.name) == ["z", "x", "y"])
    }
}

// MARK: - 侧边栏分区

@Suite("侧边栏分区构建")
struct SidebarModelTests {
    @Test("活跃项目按 sortOrder、项目内会话 createdAt 倒序、全局独立")
    func build() {
        let p1 = UUID(), p2 = UUID(), p3 = UUID()
        let now = Date()
        let projects = [
            WorkspaceTestFixtures.makeProject("P2", id: ProjectID(p2), sortOrder: 1),
            WorkspaceTestFixtures.makeProject("P1", id: ProjectID(p1), sortOrder: 0),
            WorkspaceTestFixtures.makeProject("P3", id: ProjectID(p3), archived: true, sortOrder: 2),
        ]
        let sessions = [
            WorkspaceTestFixtures.makeSession(UUID(), projectId: p1, createdAt: now.addingTimeInterval(-7200)),
            WorkspaceTestFixtures.makeSession(UUID(), projectId: p1, createdAt: now),
            WorkspaceTestFixtures.makeSession(UUID(), projectId: p2, createdAt: now),
            WorkspaceTestFixtures.makeSession(UUID(), createdAt: now),
            WorkspaceTestFixtures.makeSession(UUID(), archived: true, createdAt: now),
            WorkspaceTestFixtures.makeSession(UUID(), projectId: p3, createdAt: now),
        ]
        let model = SidebarModelBuilder.build(projects: projects, sessions: sessions)
        let sectionNames = model.projectSections.map(\.project.name)
        #expect(sectionNames == ["P1", "P2"])
        #expect(model.projectSections[0].sessions.count == 2)
        #expect(model.projectSections[0].sessions[0].metadata.createdAt >
            model.projectSections[0].sessions[1].metadata.createdAt)
        #expect(model.globalSessions.count == 1)
        let archivedNames = model.archivedProjects.map(\.name)
        #expect(archivedNames == ["P3"])
        #expect(model.archivedSessions.count == 1)
        // P3（已归档项目）内的活跃会话不进入主区（随项目进归档管理）
        #expect(!model.globalSessions.contains { $0.metadata.projectId == p3 })
    }

    @Test("折叠态保留在分区上（UI 收起依据）")
    func collapsedPreserved() {
        let p1 = UUID()
        let project = WorkspaceTestFixtures.makeProject("P", id: ProjectID(p1), collapsed: true)
        let model = SidebarModelBuilder.build(
            projects: [project],
            sessions: [WorkspaceTestFixtures.makeSession(UUID(), projectId: p1)]
        )
        #expect(model.projectSections[0].project.collapsed)
    }

    @Test("project(for:) 命中/未命中")
    func projectLookup() {
        let p1 = UUID()
        let project = WorkspaceTestFixtures.makeProject("P", id: ProjectID(p1))
        let inProject = WorkspaceTestFixtures.makeSession(UUID(), projectId: p1)
        let global = WorkspaceTestFixtures.makeSession(UUID())
        #expect(SidebarModelBuilder.project(for: inProject, in: [project])?.id == project.id)
        #expect(SidebarModelBuilder.project(for: global, in: [project]) == nil)
    }
}

// MARK: - 同步载荷（KVS LWW 元数据）

@Suite("工作区同步载荷")
struct WorkspaceSyncTests {
    let p1 = UUID(), p2 = UUID()
    let s1 = UUID(), s2 = UUID()

    private var localProjects: [Project] {
        [
            WorkspaceTestFixtures.makeProject("本地A", id: ProjectID(p1), sortOrder: 0),
        ]
    }

    private var localSessions: [SessionRecord] {
        [
            WorkspaceTestFixtures.makeSession(s1, projectId: p1),
            WorkspaceTestFixtures.makeSession(s2),
        ]
    }

    private var localAssignments: [String: SessionAssignment] {
        var m: [String: SessionAssignment] = [:]
        for session in localSessions {
            m[session.id.rawValue.uuidString] = SessionAssignment(
                projectId: session.metadata.projectId,
                archived: session.metadata.archived
            )
        }
        return m
    }

    @Test("build → encode/decode 往返一致")
    func roundTrip() throws {
        let payload = WorkspaceSyncPayload.build(projects: localProjects, sessions: localSessions)
        let data = WorkspaceSyncPayload.encode(payload)
        let decoded = try #require(WorkspaceSyncPayload.decode(data))
        #expect(decoded == payload)
        #expect(decoded.sessionAssignments.count == 2)
    }

    @Test("非法数据 decode = nil")
    func badData() {
        #expect(WorkspaceSyncPayload.decode(Data("not json".utf8)) == nil)
    }

    @Test("应用：远端新增项目 upsert、本地独有项目移除、会话归属变更检出")
    func applyChanges() throws {
        let remoteP3 = WorkspaceTestFixtures.makeProject("远端C", id: ProjectID(p2), sortOrder: 1)
        var remote = WorkspaceSyncPayload.build(projects: [remoteP3], sessions: [
            WorkspaceTestFixtures.makeSession(s1, projectId: p2), // s1 迁到远端 C
            WorkspaceTestFixtures.makeSession(s2, archived: true), // s2 归档
        ])
        remote.projects = [remoteP3]
        let changes = WorkspaceSyncPayload.applyChanges(
            currentProjects: localProjects,
            currentAssignments: localAssignments,
            payload: remote
        )
        #expect(changes.projectsToSave.map(\.name) == ["远端C"])
        #expect(changes.projectIDsToRemove == [ProjectID(p1)])
        let s1Change = try #require(changes.sessionChanges[s1])
        #expect(s1Change.projectId == p2)
        let s2Change = try #require(changes.sessionChanges[s2])
        #expect(s2Change.archived)
        #expect(s2Change.projectId == nil)
    }

    @Test("无差异 → 空变更集")
    func noDiff() {
        let payload = WorkspaceSyncPayload.build(projects: localProjects, sessions: localSessions)
        let changes = WorkspaceSyncPayload.applyChanges(
            currentProjects: localProjects,
            currentAssignments: localAssignments,
            payload: payload
        )
        #expect(changes.isEmpty)
    }

    @Test("远端修改项目字段（重命名/折叠/排序）→ 检出 upsert；未变项目不收录")
    func projectFieldDiff() {
        let p1 = UUID()
        let p2 = UUID()
        let localA = WorkspaceTestFixtures.makeProject("本地A", id: ProjectID(p1), sortOrder: 0)
        let localB = WorkspaceTestFixtures.makeProject("本地B", id: ProjectID(p2), sortOrder: 1)
        var remoteA = localA.renamedTo("远端A").withCollapsed(true)
        remoteA = remoteA.withSortOrder(9)
        let payload = WorkspaceSyncPayload.build(projects: [remoteA, localB], sessions: [
            WorkspaceTestFixtures.makeSession(UUID(), projectId: p1),
        ])
        var currentAssignments: [String: SessionAssignment] = [:]
        let localSession = WorkspaceTestFixtures.makeSession(UUID(), projectId: p1)
        currentAssignments[localSession.id.rawValue.uuidString] = SessionAssignment(
            projectId: localSession.metadata.projectId, archived: false
        )
        let changes = WorkspaceSyncPayload.applyChanges(
            currentProjects: [localA, localB],
            currentAssignments: currentAssignments,
            payload: payload
        )
        // 仅 A 有差异 → 仅 A 入 upsert 清单
        #expect(changes.projectsToSave.map(\.id) == [localA.id])
        #expect(changes.projectIDsToRemove.isEmpty)
        let saved = changes.projectsToSave[0]
        #expect(saved.name == "远端A")
        #expect(saved.collapsed)
        #expect(saved.sortOrder == 9)
    }

    @Test("载荷缺失的会话条目保持本地现状")
    func missingAssignmentKeepsLocal() {
        var payload = WorkspaceSyncPayload.build(projects: localProjects, sessions: [
            WorkspaceTestFixtures.makeSession(s1, projectId: p1),
        ])
        payload.projects = localProjects
        // s2 不在载荷中
        let changes = WorkspaceSyncPayload.applyChanges(
            currentProjects: localProjects,
            currentAssignments: localAssignments,
            payload: payload
        )
        #expect(changes.sessionChanges[s2] == nil)
        #expect(changes.sessionChanges[s1] == nil)
    }
}
