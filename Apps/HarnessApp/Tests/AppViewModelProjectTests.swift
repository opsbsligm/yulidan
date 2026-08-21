import Foundation
@testable import HarnessApp
import Session
import Testing
import Workspace

// MARK: - AppViewModel 项目模块（P0.2：新建/重命名/折叠/归档/删除二选一/拖拽迁移/搜索限定/跨实例持久）

// MARK: - 测试辅助

/// 通用轮询等待（异步 Task 持久化落库）
@MainActor
private func waitFor(_: String, timeout: TimeInterval = 10,
                     _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}

@MainActor
@Suite("AppViewModel 项目模块", .serialized)
struct AppViewModelProjectTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    // MARK: - 夹具与轮询

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-project-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-project-skills-\(UUID().uuidString)")
    }

    private func makeVM(dbURL: URL) -> AppViewModel {
        AppViewModel(skillUserDirectory: tempSkillDir(), sessionDBURL: dbURL)
    }

    /// 等待启动异步加载完成（空库 sessions 恒空：以固定短等待覆盖启动 Task）
    private func waitForReady(_: AppViewModel) async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: - 新建 / 重命名 / 折叠

    @Test("新建项目：入列表 + sortOrder 递增 + DB 持久化；空名 no-op")
    func createProjectPersists() async {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)

        vm.createProject(name: "  项目一  ")
        vm.createProject(name: "项目二")

        #expect(vm.projects.count == 2)
        #expect(vm.projects[0].name == "项目一") // 首尾空白已修剪
        #expect(vm.projects[1].name == "项目二")
        #expect(vm.projects[1].sortOrder == vm.projects[0].sortOrder + 1)

        vm.createProject(name: "   ")
        #expect(vm.projects.count == 2)

        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        let ok = await waitFor("项目行落库") {
            await (try? db.loadProjectRows())?.count == 2
        }
        #expect(ok)
    }

    @Test("重命名 / 折叠：字段更新 + 持久化")
    func renameAndCollapse() async {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)
        vm.createProject(name: "原名")
        guard let project = vm.projects.first else {
            Issue.record("项目缺失"); return
        }

        vm.renameProject(project, to: "新名")
        #expect(vm.projects[0].name == "新名")
        vm.toggleProjectCollapsed(project)
        #expect(vm.projects[0].collapsed)

        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        let ok = await waitFor("折叠态落库") {
            let rows = try? await db.loadProjectRows()
            return rows?.first(where: { $0.id == project.id.rawValue.uuidString })?.collapsed == true
        }
        #expect(ok)
    }

    // MARK: - 删除二选一

    @Test("删除项目（释放至全局）：会话归属清空 + 持久化 + 项目行删除")
    func deleteReleaseToGlobal() async {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)
        vm.createNewSession(silent: true)
        vm.createProject(name: "目标")
        guard let project = vm.projects.first else {
            Issue.record("项目缺失"); return
        }
        vm.moveSession(vm.sessions[0], to: .project(project.id))

        vm.deleteProject(project, option: .releaseToGlobal)

        #expect(vm.projects.isEmpty)
        #expect(vm.sessions.count == 1)
        #expect(vm.sessions[0].metadata.projectId == nil)

        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        let ok = await waitFor("释放落库") {
            guard let rows = try? await db.loadProjectRows() else { return false }
            guard let sessions = try? await db.loadSessions() else { return false }
            return rows.isEmpty && sessions.allSatisfy { $0.metadata.projectId == nil }
        }
        #expect(ok)
    }

    @Test("删除项目（删除全部会话）：内部会话出列表 + DB 清理，全局会话保留")
    func deleteAllSessions() async throws {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)
        vm.createNewSession(silent: true) // 会话 1（将入项目）
        vm.createNewSession(silent: true) // 会话 2（全局保留）
        vm.createProject(name: "目标")
        guard let project = vm.projects.first else {
            Issue.record("项目缺失"); return
        }
        try vm.moveSession(#require(vm.sessions.first { $0.metadata.projectId == nil }), to: .project(project.id))
        #expect(vm.sessions.count == 2)

        vm.deleteProject(project, option: .deleteAllSessions)

        #expect(vm.projects.isEmpty)
        #expect(vm.sessions.count == 1)
        #expect(vm.sessions[0].metadata.projectId == nil)

        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        let ok = await waitFor("DB 清理完成") {
            guard let rows = try? await db.loadProjectRows() else { return false }
            guard let sessions = try? await db.loadSessions() else { return false }
            return rows.isEmpty && sessions.count == 1
                && !sessions.contains { $0.metadata.projectId == project.id.rawValue }
        }
        #expect(ok)
    }

    // MARK: - 拖拽迁移

    @Test("moveSession：全局→项目 / 跨项目 A→B / 项目→全局（含 DB 持久化）")
    func moveSessionMatrix() async {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)
        vm.createNewSession(silent: true)
        vm.createProject(name: "A")
        vm.createProject(name: "B")
        guard let a = vm.projects.first, let b = vm.projects.last else {
            Issue.record("项目缺失"); return
        }
        guard let session = vm.sessions.first else {
            Issue.record("会话缺失"); return
        }

        // 同目标 no-op
        vm.moveSession(session, to: .global)
        #expect(vm.sessions[0].metadata.projectId == nil)

        // 全局 → A
        vm.moveSession(vm.sessions[0], to: .project(a.id))
        #expect(vm.sessions[0].metadata.projectId == a.id.rawValue)

        // A → B（跨项目）
        vm.moveSession(vm.sessions[0], to: .project(b.id))
        #expect(vm.sessions[0].metadata.projectId == b.id.rawValue)

        // B → 全局
        vm.moveSession(vm.sessions[0], to: .global)
        #expect(vm.sessions[0].metadata.projectId == nil)

        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        vm.moveSession(vm.sessions[0], to: .project(a.id))
        let ok = await waitFor("迁移落库") {
            guard let sessions = try? await db.loadSessions() else { return false }
            return sessions.first { $0.id == session.id }?.metadata.projectId == a.id.rawValue
        }
        #expect(ok)
    }

    // MARK: - 归档 / 取消归档回落

    @Test("项目归档：主区剔除；取消归档回落展示尾部")
    func projectArchiveToggle() async {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)
        vm.createProject(name: "甲")
        vm.createProject(name: "乙")
        guard let jia = vm.projects.first else {
            Issue.record("项目缺失"); return
        }

        vm.toggleProjectArchived(jia)
        let model = SidebarModelBuilder.build(projects: vm.projects, sessions: vm.sessions)
        #expect(model.projectSections.map(\.project.name) == ["乙"])
        #expect(model.archivedProjects.map(\.name) == ["甲"])

        guard let archived = vm.projects.first(where: \.archived) else {
            Issue.record("归档项目缺失"); return
        }
        vm.unarchiveProject(archived)
        let model2 = SidebarModelBuilder.build(projects: vm.projects, sessions: vm.sessions)
        #expect(model2.projectSections.map(\.project.name) == ["乙", "甲"])
        #expect(model2.archivedProjects.isEmpty)
    }

    @Test("会话取消归档：原项目存活 → 回原项目；原项目已删 → 回落全局")
    func unarchiveSessionFallback() async throws {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)
        vm.createNewSession(silent: true)
        vm.createNewSession(silent: true)
        vm.createProject(name: "甲")
        vm.createProject(name: "乙")
        guard let jia = vm.projects.first, let yi = vm.projects.last else {
            Issue.record("项目缺失"); return
        }
        vm.moveSession(vm.sessions[0], to: .project(jia.id))
        vm.moveSession(vm.sessions[1], to: .project(yi.id))
        let inJia = vm.sessions[0]
        let inYi = vm.sessions[1]

        // 归档会话 1（甲内）→ 取消归档 → 回甲
        vm.toggleSessionArchived(inJia)
        #expect(vm.sessions.first { $0.id == inJia.id }?.metadata.archived == true)
        try vm.unarchiveSession(#require(vm.sessions.first { $0.id == inJia.id }))
        let restored1 = try #require(vm.sessions.first { $0.id == inJia.id })
        #expect(restored1.metadata.archived == false)
        #expect(restored1.metadata.projectId == jia.id.rawValue)

        // 归档会话 2 → 删除乙（释放全局）→ 取消归档 → 原项目已删 → 全局
        vm.toggleSessionArchived(inYi)
        vm.deleteProject(yi, option: .releaseToGlobal)
        try vm.unarchiveSession(#require(vm.sessions.first { $0.id == inYi.id }))
        let restored2 = try #require(vm.sessions.first { $0.id == inYi.id })
        #expect(restored2.metadata.archived == false)
        #expect(restored2.metadata.projectId == nil)
    }

    // MARK: - 搜索限定项目

    @Test("搜索限定项目：命中仅限目标项目")
    func searchScope() async {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm)
        vm.createNewSession(silent: true) // 会话 1（将入甲）
        vm.createNewSession(silent: true) // 会话 2（全局）
        vm.createProject(name: "甲")
        guard let jia = vm.projects.first else {
            Issue.record("项目缺失"); return
        }
        vm.moveSession(vm.sessions[0], to: .project(jia.id))
        // 两会话均无用户消息 → 展示标题同为"新对话"

        vm.handleSessionSearch("新对话")
        let globalOK = await waitFor("全局搜索") { vm.searchResults != nil }
        #expect(globalOK)
        #expect(vm.searchResults?.count == 2)

        vm.handleSessionSearch("新对话", projectScope: jia.id.rawValue)
        let scopedOK = await waitFor("限定搜索") {
            vm.searchResults != nil && vm.searchResults!.allSatisfy {
                $0.metadata.projectId == jia.id.rawValue
            }
        }
        #expect(scopedOK)
        #expect(vm.searchResults?.allSatisfy { $0.metadata.projectId == jia.id.rawValue } == true)
        #expect(vm.searchResults?.count == 1)
    }

    // MARK: - 跨实例持久

    @Test("跨实例：项目 + 会话归属在重载后保持")
    func crossInstancePersistence() async {
        let dbURL = tempDBURL()
        let vm1 = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        await waitForReady(vm1)
        vm1.createNewSession(silent: true)
        vm1.createProject(name: "持久甲")
        guard let project = vm1.projects.first else {
            Issue.record("项目缺失"); return
        }
        vm1.moveSession(vm1.sessions[0], to: .project(project.id))

        guard let db = vm1.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        let ok = await waitFor("归属落库") {
            guard let rows = try? await db.loadProjectRows() else { return false }
            guard let sessions = try? await db.loadSessions() else { return false }
            return rows.count == 1
                && sessions.first { $0.metadata.projectId == project.id.rawValue } != nil
        }
        #expect(ok)

        let vm2 = makeVM(dbURL: dbURL)
        await waitForReady(vm2)
        #expect(vm2.projects.map(\.name) == ["持久甲"])
        #expect(vm2.sessions.first?.metadata.projectId == project.id.rawValue)
    }
}

// MARK: - AppWorkspaceStore（同步存储投影：读/写/删除释放语义）

@MainActor
@Suite("AppWorkspaceStore", .serialized)
struct AppWorkspaceStoreTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-wsstore-test-\(UUID().uuidString).sqlite")
    }

    private func makeVM(dbURL: URL) -> AppViewModel {
        AppViewModel(
            skillUserDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-wsstore-skills-\(UUID().uuidString)"),
            sessionDBURL: dbURL
        )
    }

    @Test("loadProjects / loadSessionAssignments 与 DB 一致")
    func projectionsMatchDB() async throws {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try? await Task.sleep(for: .milliseconds(300))
        vm.createNewSession(silent: true)
        vm.createProject(name: "甲")
        guard let project = vm.projects.first else {
            Issue.record("项目缺失"); return
        }
        vm.moveSession(vm.sessions[0], to: .project(project.id))

        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        _ = await waitFor("归属落库") {
            guard let sessions = try? await db.loadSessions() else { return false }
            return sessions.first?.metadata.projectId == project.id.rawValue
        }

        let store = AppWorkspaceStore(db: db)
        let projects = try await store.loadProjects()
        #expect(projects.map(\.name) == ["甲"])
        let assignments = try await store.loadSessionAssignments()
        #expect(assignments.count == 1)
        guard let (key, value) = assignments.first else {
            Issue.record("assignments 空"); return
        }
        #expect(value.projectId == project.id.rawValue)
        #expect(UUID(uuidString: key) != nil)
    }

    @Test("apply：远端 upsert + 归属变更落 DB；项目删除释放内部会话")
    func applyChangeSet() async throws {
        let dbURL = tempDBURL()
        let vm = makeVM(dbURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try? await Task.sleep(for: .milliseconds(300))
        vm.createNewSession(silent: true)
        vm.createNewSession(silent: true)
        vm.createProject(name: "本地甲")
        vm.createProject(name: "本地乙")
        guard let localA = vm.projects.first, let localB = vm.projects.last else {
            Issue.record("项目缺失"); return
        }
        vm.moveSession(vm.sessions[0], to: .project(localA.id))
        vm.moveSession(vm.sessions[1], to: .project(localB.id))

        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 缺失"); return
        }
        _ = await waitFor("归属落库") {
            guard let sessions = try? await db.loadSessions() else { return false }
            return sessions.count == 2
        }
        let store = AppWorkspaceStore(db: db)

        // 远端 upsert 新项目 + 会话 1 归属变更至新项目
        let remoteNew = Project(name: "远端丙", sortOrder: 9)
        var changes = WorkspaceChangeSet()
        changes.projectsToSave = [remoteNew]
        let sessionID = vm.sessions[0].id.rawValue
        changes.sessionChanges[sessionID] = WorkspaceSyncPayload.SessionChange(
            sessionId: sessionID, projectId: remoteNew.id.rawValue, archived: false
        )
        try await store.apply(changes)

        let projects = try await store.loadProjects()
        #expect(projects.map(\.name).contains("远端丙"))
        let sessions = try await db.loadSessions()
        let moved = try #require(sessions.first { $0.id.rawValue == sessionID })
        #expect(moved.metadata.projectId == remoteNew.id.rawValue)

        // 删除本地乙 → 内部会话（会话 2）释放至全局
        var changes2 = WorkspaceChangeSet()
        changes2.projectIDsToRemove = [localB.id]
        try await store.apply(changes2)
        let projects2 = try await store.loadProjects()
        #expect(!projects2.map(\.name).contains("本地乙"))
        let sessions2 = try await db.loadSessions()
        let released = try #require(sessions2.first { $0.id == vm.sessions[1].id })
        #expect(released.metadata.projectId == nil)
    }
}
