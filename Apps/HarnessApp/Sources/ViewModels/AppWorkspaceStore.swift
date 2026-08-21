import Account
import Foundation
import Session
import Workspace

/// 工作区同步存储的生产实现：以 SessionDB（actor，串行队列）为唯一事实源。
/// 线程安全：本类无可变状态；全部读写经 SessionDB 串行化。
///
/// 注意：`SessionDB.save` 为全量保存（事件表重写），故任何 metadata 修改
/// 必须先 load 完整记录（含事件）再 patch metadata，禁止保存元数据骨架记录。
final class AppWorkspaceStore: WorkspaceStateStoring, @unchecked Sendable {
    private let db: SessionDB

    init(db: SessionDB) {
        self.db = db
    }

    func loadProjects() async throws -> [Project] {
        let rows = try await db.loadProjectRows()
        return rows.map { Project(row: $0) }
    }

    func loadSessionAssignments() async throws -> [String: SessionAssignment] {
        let sessions = try await db.loadSessions()
        var out: [String: SessionAssignment] = [:]
        for session in sessions {
            out[session.id.rawValue.uuidString] = SessionAssignment(
                projectId: session.metadata.projectId,
                archived: session.metadata.archived
            )
        }
        return out
    }

    func apply(_ changes: WorkspaceChangeSet) async throws {
        // 1. 项目 upsert（仅差异项）
        for project in changes.projectsToSave {
            try await db.saveProjectRow(project.row)
        }
        // 2. 项目删除：先释放内部会话至全局（防悬挂引用），再删项目行
        for id in changes.projectIDsToRemove {
            let rawID = id.rawValue
            let sessions = try await db.loadSessions()
            for session in sessions where session.metadata.projectId == rawID {
                try await db.save(
                    Self.patch(session, metadata: session.metadata.withProject(nil))
                )
            }
            try await db.deleteProjectRow(id: rawID.uuidString)
        }
        // 3. 会话归属/归档变更：load 完整记录 → patch metadata → 全量保存
        for (sessionID, change) in changes.sessionChanges {
            guard let current = try await db.load(SessionID(rawValue: sessionID)) else {
                continue
            }
            let meta = current.metadata
                .withProject(change.projectId)
                .withArchived(change.archived)
            try await db.save(Self.patch(current, metadata: meta))
        }
    }

    /// 保持事件/轮次/状态不变，仅替换 metadata（防 save 全量重写清空事件）
    private static func patch(_ record: SessionRecord, metadata: SessionMetadata) -> SessionRecord {
        SessionRecord(
            id: record.id,
            metadata: metadata,
            events: record.events,
            currentTurn: record.currentTurn,
            currentStep: record.currentStep,
            status: record.status
        )
    }
}
