@testable import Account
import Foundation
import Testing
import Workspace

// MARK: - 测试 Fakes

enum WorkspaceStoreError: Error {
    case loadFailed
}

/// 内存工作区存储（记录全部 apply 调用，并同步更新内存投影）
final class FakeWorkspaceStore: WorkspaceStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _projects: [Project]
    private var _assignments: [String: SessionAssignment]
    private var _applied: [WorkspaceChangeSet] = []
    private var _failLoad = false

    init(projects: [Project] = [], assignments: [String: SessionAssignment] = [:]) {
        _projects = projects
        _assignments = assignments
    }

    var projects: [Project] {
        lock.lock(); defer { lock.unlock() }
        return _projects
    }

    var assignments: [String: SessionAssignment] {
        lock.lock(); defer { lock.unlock() }
        return _assignments
    }

    var applied: [WorkspaceChangeSet] {
        lock.lock(); defer { lock.unlock() }
        return _applied
    }

    var applyCount: Int {
        applied.count
    }

    var failLoad: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _failLoad
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _failLoad = newValue
        }
    }

    func loadProjects() throws -> [Project] {
        if failLoad {
            throw WorkspaceStoreError.loadFailed
        }
        return projects
    }

    func loadSessionAssignments() throws -> [String: SessionAssignment] {
        if failLoad {
            throw WorkspaceStoreError.loadFailed
        }
        return assignments
    }

    func apply(_ changes: WorkspaceChangeSet) throws {
        lock.lock()
        defer { lock.unlock() }
        _applied.append(changes)
        var byID = Dictionary(uniqueKeysWithValues: _projects.map { ($0.id, $0) })
        for project in changes.projectsToSave {
            byID[project.id] = project
        }
        for id in changes.projectIDsToRemove {
            byID[id] = nil
        }
        _projects = Array(byID.values).sorted {
            ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name)
        }
        for (id, change) in changes.sessionChanges {
            _assignments[id.uuidString] = SessionAssignment(
                projectId: change.projectId, archived: change.archived
            )
        }
    }
}

// MARK: - 引擎测试

@Suite("WorkspaceSyncEngine")
struct WorkspaceSyncEngineTests {
    private let pA = UUID()
    private let pC = UUID()
    private let s1 = UUID()
    /// 固定创建时间：Project 默认 createdAt=Date() 会导致每次取值不等
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var projectA: Project {
        Project(id: ProjectID(pA), name: "项目A", createdAt: fixedDate,
                archived: false, collapsed: false, sortOrder: 0)
    }

    private var projectC: Project {
        Project(id: ProjectID(pC), name: "远端C", createdAt: fixedDate,
                archived: false, collapsed: false, sortOrder: 1)
    }

    private var localAssignment: SessionAssignment {
        SessionAssignment(projectId: pA, archived: false)
    }

    private func makeTempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("workspace-sync-\(UUID().uuidString)")
    }

    private func makeEngine(
        kvs: FakeKVS,
        store: FakeWorkspaceStore
    ) -> (MetadataSyncService, WorkspaceSyncEngine, URL) {
        let temp = makeTempDir()
        let sync = MetadataSyncService(store: kvs, stagingDir: temp, deviceId: "device-test")
        return (sync, WorkspaceSyncEngine(sync: sync, store: store), temp)
    }

    @Test("publishLocalState：KVS 落 workspace.v1 且载荷内容=本地状态")
    func publishLocalState() async throws {
        let kvs = FakeKVS()
        let store = FakeWorkspaceStore(
            projects: [projectA],
            assignments: [s1.uuidString: localAssignment]
        )
        let (_, engine, temp) = makeEngine(kvs: kvs, store: store)
        defer { try? FileManager.default.removeItem(at: temp) }

        await engine.publishLocalState()

        let raw = try #require(kvs.data(forKey: WorkspaceSyncPayload.kvsKey))
        let wrapped = try #require(try? JSONDecoder().decode(SyncedValue.self, from: raw))
        let payload = try #require(WorkspaceSyncPayload.decode(wrapped.value))
        #expect(payload.projects == [projectA])
        #expect(payload.sessionAssignments[s1.uuidString] == localAssignment)
    }

    @Test("applyRemoteValue：远端新增项目 upsert + 会话归属变更落 store")
    func applyRemoteAddAndMove() async throws {
        let kvs = FakeKVS()
        let store = FakeWorkspaceStore(
            projects: [projectA],
            assignments: [s1.uuidString: localAssignment]
        )
        let (_, engine, temp) = makeEngine(kvs: kvs, store: store)
        defer { try? FileManager.default.removeItem(at: temp) }

        let remote = WorkspaceSyncPayload(
            projects: [projectA, projectC],
            sessionAssignments: [s1.uuidString: SessionAssignment(projectId: pC, archived: false)]
        )
        await engine.applyRemoteValue(WorkspaceSyncPayload.encode(remote))

        let applied = try #require(store.applied.last)
        #expect(applied.projectsToSave.map(\.id) == [projectC.id])
        #expect(applied.projectIDsToRemove.isEmpty)
        let change = try #require(applied.sessionChanges[s1])
        #expect(change.projectId == pC)
        #expect(change.archived == false)
        // 内存投影同步更新
        #expect(store.projects.map(\.name) == ["项目A", "远端C"])
        #expect(store.assignments[s1.uuidString]?.projectId == pC)
    }

    @Test("applyRemoteValue：远端删除本地项目 → 变更集含删除项")
    func applyRemoteRemovesLocalProject() async throws {
        let kvs = FakeKVS()
        let store = FakeWorkspaceStore(
            projects: [projectA, projectC],
            assignments: [s1.uuidString: localAssignment]
        )
        let (_, engine, temp) = makeEngine(kvs: kvs, store: store)
        defer { try? FileManager.default.removeItem(at: temp) }

        let remote = WorkspaceSyncPayload(
            projects: [projectA],
            sessionAssignments: [s1.uuidString: localAssignment]
        )
        await engine.applyRemoteValue(WorkspaceSyncPayload.encode(remote))

        let applied = try #require(store.applied.last)
        #expect(applied.projectIDsToRemove == [ProjectID(pC)])
        #expect(applied.projectsToSave.isEmpty)
        #expect(store.projects == [projectA])
    }

    @Test("applyRemoteValue：坏数据 no-op，本地状态不被污染")
    func badDataNoOp() async {
        let kvs = FakeKVS()
        let store = FakeWorkspaceStore(
            projects: [projectA],
            assignments: [s1.uuidString: localAssignment]
        )
        let (_, engine, temp) = makeEngine(kvs: kvs, store: store)
        defer { try? FileManager.default.removeItem(at: temp) }

        await engine.applyRemoteValue(Data("not json".utf8))

        #expect(store.applyCount == 0)
        #expect(store.projects == [projectA])
    }

    @Test("applyRemoteValue：远端与本地无差异 → 不触发 apply")
    func noDiffNoOp() async {
        let kvs = FakeKVS()
        let store = FakeWorkspaceStore(
            projects: [projectA],
            assignments: [s1.uuidString: localAssignment]
        )
        let (_, engine, temp) = makeEngine(kvs: kvs, store: store)
        defer { try? FileManager.default.removeItem(at: temp) }

        let remote = WorkspaceSyncPayload(
            projects: [projectA],
            sessionAssignments: [s1.uuidString: localAssignment]
        )
        await engine.applyRemoteValue(WorkspaceSyncPayload.encode(remote))

        #expect(store.applyCount == 0)
    }

    @Test("applyRemoteValue：本地读取失败 → 静默 no-op")
    func storeLoadFailureNoOp() async {
        let kvs = FakeKVS()
        let store = FakeWorkspaceStore(
            projects: [projectA],
            assignments: [s1.uuidString: localAssignment]
        )
        store.failLoad = true
        let (_, engine, temp) = makeEngine(kvs: kvs, store: store)
        defer { try? FileManager.default.removeItem(at: temp) }

        await engine.applyRemoteValue(WorkspaceSyncPayload.encode(
            WorkspaceSyncPayload(projects: [], sessionAssignments: [:])
        ))

        #expect(store.applyCount == 0)
    }
}

// MARK: - AccountService 挂接测试

@MainActor
@Suite("AccountService 工作区挂接")
struct AccountWorkspaceAttachTests {
    @Test("本地模式 attach 返回 nil（未激活同步）")
    func attachInLocalModeReturnsNil() throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()

        let engine = fx.service.attachWorkspaceStore(FakeWorkspaceStore())

        #expect(engine == nil)
    }

    @Test("icloudReady 后 attach 返回引擎且幂等")
    func attachInICloudReadyReturnsSameEngine() async throws {
        let fx = try AccountServiceFixture()
        defer { fx.cleanup() }
        fx.service.restore()
        fx.service.signInWithApple()
        try await Task.sleep(for: .milliseconds(200))

        let store = FakeWorkspaceStore()
        let engine1 = fx.service.attachWorkspaceStore(store)
        #expect(engine1 != nil)
        // 幂等：重复挂接返回既有引擎
        let engine2 = fx.service.attachWorkspaceStore(store)
        #expect(engine1 === engine2)
    }
}
