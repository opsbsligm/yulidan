import Foundation
import GRDB

/// 会话持久化 — GRDB.swift (SQLite) 实现
/// 数据库位置：~/Library/Application Support/Harness/sessions.sqlite
/// 表结构：
///   sessions(id TEXT PK, metadata_json TEXT, turn INT, status TEXT, created_at REAL)
///   events(session_id TEXT, seq INT, payload TEXT, PK(session_id, seq))
public actor SessionDB {
    private let dbQueue: DatabaseQueue
    public let dbURL: URL

    public init(dbURL: URL? = nil) throws {
        if let dbURL {
            self.dbURL = dbURL
        } else {
            let fm = FileManager.default
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Harness", isDirectory: true)
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            self.dbURL = base.appendingPathComponent("sessions.sqlite")
        }
        let q: DatabaseQueue
        do {
            q = try DatabaseQueue(path: self.dbURL.path)
        } catch {
            throw SessionDBError.openFailed(error.localizedDescription)
        }
        try Self.migrate(q)
        dbQueue = q
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("metadata_json", .text).notNull()
                t.column("turn", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("created_at", .double).notNull()
            }
            try db.create(table: "events") { t in
                t.column("session_id", .text).notNull()
                t.column("seq", .integer).notNull()
                t.column("payload", .text).notNull()
                t.primaryKey(["session_id", "seq"])
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - 读写 API

    /// 加载会话列表（仅元数据，不含事件）— 单条 SQL，无按会话的额外查询。
    /// 启动侧边栏列表专用；事件明细按需经 load(_:) 拉取，避免启动时全量解码全部会话事件
    public func loadSessions() throws -> [SessionRecord] {
        try dbQueue.read { db in
            let rows = try sessionRows(db)
            return rows.compactMap { mapRow($0, events: []) }
        }
    }

    /// 加载单个会话（含事件，按 seq 升序）
    public func load(_ id: SessionID) throws -> SessionRecord? {
        try dbQueue.read { db in
            let sreq: SQLRequest<Row> = SQLRequest(
                sql: "SELECT * FROM sessions WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
            guard let rd = try sreq.fetchOne(db) else { return nil }
            let ereq: SQLRequest<Row> = SQLRequest(
                sql: "SELECT payload FROM events WHERE session_id = ? ORDER BY seq",
                arguments: [id.rawValue.uuidString]
            )
            var events: [SessionEvent] = []
            for erd in try ereq.fetchAll(db) {
                if let p = erd["payload"] as? String,
                   let d = p.data(using: .utf8),
                   let e = try? JSONDecoder().decode(SessionEvent.self, from: d) {
                    events.append(e)
                }
            }
            return mapRow(rd, events: events)
        }
    }

    /// 加载全部会话（含事件，按创建时间倒序）
    public func loadAll() throws -> [SessionRecord] {
        try dbQueue.read { db in
            let rows = try sessionRows(db)
            var result: [SessionRecord] = []
            for rd in rows {
                let idStr = rd["id"] as? String ?? ""
                var events: [SessionEvent] = []
                let ereq: SQLRequest<Row> = SQLRequest(
                    sql: "SELECT payload FROM events WHERE session_id = ? ORDER BY seq",
                    arguments: [idStr]
                )
                let erows = try ereq.fetchAll(db)
                for erd in erows {
                    if let p = erd["payload"] as? String,
                       let d = p.data(using: .utf8),
                       let e = try? JSONDecoder().decode(SessionEvent.self, from: d) {
                        events.append(e)
                    }
                }
                if let record = mapRow(rd, events: events) {
                    result.append(record)
                }
            }
            return result
        }
    }

    private func sessionRows(_ db: Database) throws -> [Row] {
        let request: SQLRequest<Row> = "SELECT * FROM sessions ORDER BY created_at DESC"
        return try request.fetchAll(db)
    }

    private func mapRow(_ rd: Row, events: [SessionEvent]) -> SessionRecord? {
        let idStr = rd["id"] as? String ?? ""
        let metadataJSON = rd["metadata_json"] as? String ?? ""
        let turn: Int? = rd["turn"]
        let status: String? = rd["status"]
        guard let metaData = metadataJSON.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(SessionMetadata.self, from: metaData)
        else {
            return nil
        }
        let id = SessionID(rawValue: UUID(uuidString: idStr) ?? UUID())
        return SessionRecord(
            id: id,
            metadata: metadata,
            events: events,
            currentTurn: turn ?? 0,
            status: SessionStatus(rawValue: status ?? "active") ?? .active
        )
    }

    /// 全量保存一个会话（会话行 upsert + 事件表重写）
    public func save(_ session: SessionRecord) throws {
        try dbQueue.write { db in
            let metaJSON = String(data: (try? JSONEncoder().encode(session.metadata)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
            try db.execute(
                sql: """
                INSERT INTO sessions (id, metadata_json, turn, status, created_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    metadata_json = excluded.metadata_json,
                    turn = excluded.turn,
                    status = excluded.status
                """,
                arguments: [
                    session.id.rawValue.uuidString,
                    metaJSON,
                    session.currentTurn,
                    session.status.rawValue,
                    session.metadata.createdAt.timeIntervalSince1970,
                ]
            )
            try db.execute(sql: "DELETE FROM events WHERE session_id = ?",
                           arguments: [session.id.rawValue.uuidString])
            for (i, event) in session.events.enumerated() {
                let payload = String(data: (try? JSONEncoder().encode(event)) ?? Data(), encoding: .utf8) ?? ""
                try db.execute(
                    sql: "INSERT OR REPLACE INTO events (session_id, seq, payload) VALUES (?, ?, ?)",
                    arguments: [session.id.rawValue.uuidString, i, payload]
                )
            }
        }
    }

    /// 搜索会话：匹配标题（metadata）或事件正文（LIKE，ASCII 大小写不敏感），按创建时间倒序
    public func search(query: String, limit: Int = 50) throws -> [SessionRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let like = "%\(Self.escapeLike(trimmed))%"
        return try dbQueue.read { db in
            let req: SQLRequest<Row> = SQLRequest(sql: """
            SELECT * FROM sessions
            WHERE id IN (
                SELECT id FROM sessions WHERE metadata_json LIKE ? ESCAPE '\\'
                UNION
                SELECT session_id FROM events WHERE payload LIKE ? ESCAPE '\\'
            )
            ORDER BY created_at DESC
            LIMIT ?
            """, arguments: [like, like, limit])
            let rows = try req.fetchAll(db)
            return rows.compactMap { self.mapRow($0, events: []) }
        }
    }

    /// LIKE 通配符转义（% / _ / 反斜杠）
    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    public func delete(_ id: SessionID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM events WHERE session_id = ?", arguments: [id.rawValue.uuidString])
            try db.execute(sql: "DELETE FROM sessions WHERE id = ?", arguments: [id.rawValue.uuidString])
        }
    }
}

public enum SessionDBError: Error, LocalizedError {
    case openFailed(String)
    public var errorDescription: String? {
        switch self {
        case let .openFailed(m): "会话数据库打开失败：\(m)"
        }
    }
}
