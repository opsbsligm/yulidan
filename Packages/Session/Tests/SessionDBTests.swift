import GRDB
@testable import Session
import XCTest

/// SessionDB 持久化测试：save / loadAll / delete 往返
final class SessionDBTests: XCTestCase {
    // 测试夹具：setUp 中赋值，XCTest 标准模式
    // swiftlint:disable implicitly_unwrapped_optional
    private var dbURL: URL!
    private var db: SessionDB!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-test-\(UUID().uuidString).sqlite")
        db = try SessionDB(dbURL: dbURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    func testSaveAndLoadRoundTrip() async throws {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var session = SessionRecord(id: SessionID(), metadata: meta)
        session.append(.userMessage(UserMessage(content: [.text("你好，Harness")])))
        session.append(.assistantMessage(AssistantMessage(
            turn: 1, step: 0, content: [.text("你好！有什么可以帮你？")],
            provider: "deepseek", model: "deepseek-chat"
        )))
        session.currentTurn = 1
        try await db.save(session)

        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, session.id)
        XCTAssertEqual(loaded[0].currentTurn, 1)
        XCTAssertEqual(loaded[0].events.count, 2)
        if case let .userMessage(m) = try XCTUnwrap(loaded[0].events.first) {
            if case let .text(t) = try XCTUnwrap(m.content.first) {
                XCTAssertEqual(t, "你好，Harness")
            } else {
                XCTFail("expected text block")
            }
        }
    }

    func testUpsertRewritesEvents() async throws {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var session = SessionRecord(id: SessionID(), metadata: meta)
        session.append(.userMessage(UserMessage(content: [.text("第一条")])))
        try await db.save(session)

        session.append(.userMessage(UserMessage(content: [.text("第二条")])))
        try await db.save(session)

        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded[0].events.count, 2)
    }

    func testDelete() async throws {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        let session = SessionRecord(id: SessionID(), metadata: meta)
        try await db.save(session)
        try await db.delete(session.id)
        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded.count, 0)
    }

    func testMultipleSessionsOrdered() async throws {
        let m1 = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"), createdAt: Date().addingTimeInterval(-100))
        let m2 = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"), createdAt: Date())
        try await db.save(SessionRecord(id: SessionID(), metadata: m1))
        try await db.save(SessionRecord(id: SessionID(), metadata: m2))
        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertGreaterThan(loaded[0].metadata.createdAt, loaded[1].metadata.createdAt)
    }

    // MARK: - 损坏行防御与错误本地化（覆盖审计轮）

    /// metadata_json 损坏的行应被 mapRow 静默跳过（不崩溃、不产畸形记录）
    func testCorruptedMetadataRowSkipped() async throws {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var session = SessionRecord(id: SessionID(), metadata: meta)
        session.append(.userMessage(UserMessage(content: [.text("探针")])))
        try await db.save(session)

        // GRDB 直连同库把 metadata_json 写成非法 JSON（模拟损坏行/脏数据）
        let sid = session.id.rawValue.uuidString
        let raw = try DatabaseQueue(path: dbURL.path)
        try await raw.write { d in
            try d.execute(
                sql: "UPDATE sessions SET metadata_json = ? WHERE id = ?",
                arguments: ["{corrupted-not-json", sid]
            )
        }

        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded.count, 0, "损坏元数据的行应被跳过而非崩溃")
        let single = try await db.load(session.id)
        XCTAssertNil(single, "load(_:) 对损坏会话应返回 nil")
    }

    /// openFailed 错误本地化文案
    func testOpenFailedErrorDescription() {
        let err = SessionDBError.openFailed("磁盘已满")
        XCTAssertEqual(err.errorDescription, "会话数据库打开失败：磁盘已满")
    }

    // MARK: - 元数据快速路径（性能）

    private func makeSession(_ label: String, createdAt: Date, eventCount: Int) -> SessionRecord {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"), createdAt: createdAt)
        var session = SessionRecord(id: SessionID(), metadata: meta)
        for i in 0 ..< eventCount {
            session.append(.userMessage(UserMessage(content: [.text("\(label)-\(i)")])))
            session.append(.assistantMessage(AssistantMessage(
                turn: i + 1, step: 0, content: [.text("reply-\(label)-\(i)")],
                provider: "deepseek", model: "deepseek-chat"
            )))
        }
        session.currentTurn = eventCount
        return session
    }

    func testLoadSessionsReturnsMetadataOnly() async throws {
        let now = Date()
        let a = makeSession("a", createdAt: now.addingTimeInterval(-20), eventCount: 3)
        let b = makeSession("b", createdAt: now.addingTimeInterval(-10), eventCount: 2)
        let c = makeSession("c", createdAt: now, eventCount: 1)
        for session in [a, b, c] {
            try await db.save(session)
        }

        let loaded = try await db.loadSessions()
        XCTAssertEqual(loaded.count, 3)
        // 按创建时间倒序
        XCTAssertEqual(loaded.map(\.id), [c.id, b.id, a.id])
        // 元数据完整、事件未加载
        XCTAssertTrue(loaded.allSatisfy(\.events.isEmpty))
        XCTAssertEqual(loaded.map(\.currentTurn), [1, 2, 3])
        // 与完整加载的元数据一致
        let full = try await db.loadAll()
        XCTAssertEqual(loaded.map(\.id), full.map(\.id))
        XCTAssertEqual(loaded.map(\.currentTurn), full.map(\.currentTurn))
        XCTAssertEqual(loaded.map(\.status), full.map(\.status))
    }

    func testLoadSingleSessionWithEvents() async throws {
        let session = makeSession("solo", createdAt: Date(), eventCount: 4)
        try await db.save(session)

        let loaded = try await db.load(session.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.events.count, 8)
        // 校验事件顺序与内容：首条 userMessage / 末条 assistantMessage
        let first = try XCTUnwrap(loaded?.events.first)
        if case let .userMessage(fm) = first {
            if case let .text(t) = try XCTUnwrap(fm.content.first) {
                XCTAssertEqual(t, "solo-0")
            } else {
                XCTFail("expected text block")
            }
        } else {
            XCTFail("expected userMessage first")
        }
        let last = try XCTUnwrap(loaded?.events.last)
        if case let .assistantMessage(lm) = last {
            if case let .text(t) = try XCTUnwrap(lm.content.first) {
                XCTAssertEqual(t, "reply-solo-3")
            } else {
                XCTFail("expected text block")
            }
        } else {
            XCTFail("expected assistantMessage last")
        }

        let missing = try await db.load(SessionID())
        XCTAssertNil(missing)
    }

    func testLoadSessionsFastOnLargeDataset() async throws {
        let now = Date()
        for i in 0 ..< 300 {
            let session = makeSession("s\(i)", createdAt: now.addingTimeInterval(Double(i)), eventCount: 40)
            try await db.save(session)
        }
        let start = Date()
        let loaded = try await db.loadSessions()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(loaded.count, 300)
        XCTAssertEqual(loaded.reduce(0) { $0 + $1.events.count }, 0)
        // 宽松阈值：元数据路径不应随事件总量增长（300 会话 × 80 事件下应远快于全量解码）
        XCTAssertLessThan(elapsed, 1.0, "loadSessions took \(elapsed)s, expected < 1.0s")
    }

    func testSearchMatchesEventContent() async throws {
        let meta1 = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var s1 = SessionRecord(id: SessionID(), metadata: meta1)
        s1.append(.userMessage(UserMessage(content: [.text("Kubernetes 集群迁移方案")])))
        let meta2 = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var s2 = SessionRecord(id: SessionID(), metadata: meta2)
        s2.append(.userMessage(UserMessage(content: [.text("写个排序函数")])))
        try await db.save(s1)
        try await db.save(s2)

        let hits = try await db.search(query: "Kubernetes")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].id, s1.id)
        // ASCII 大小写不敏感
        let hitsLower = try await db.search(query: "kubernetes")
        XCTAssertEqual(hitsLower.count, 1)
        XCTAssertEqual(hitsLower[0].id, s1.id)
    }

    func testSearchNoMatchAndEmptyQuery() async throws {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var s1 = SessionRecord(id: SessionID(), metadata: meta)
        s1.append(.userMessage(UserMessage(content: [.text("存在的内容")])))
        try await db.save(s1)
        let none = try await db.search(query: "不存在的词")
        XCTAssertTrue(none.isEmpty)
        let blank = try await db.search(query: "   ")
        XCTAssertTrue(blank.isEmpty)
    }

    func testSearchRespectsLimit() async throws {
        for i in 0 ..< 5 {
            let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
            var s = SessionRecord(id: SessionID(), metadata: meta)
            s.append(.userMessage(UserMessage(content: [.text("共同主题\(i)")])))
            try await db.save(s)
        }
        let hits = try await db.search(query: "共同主题", limit: 3)
        XCTAssertEqual(hits.count, 3)
    }

    func testSearchEscapesLikeWildcards() async throws {
        // 正文含 % 与 _，必须按字面量检索
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var s1 = SessionRecord(id: SessionID(), metadata: meta)
        s1.append(.userMessage(UserMessage(content: [.text("进度 50% 的 a_b 报告")])))
        try await db.save(s1)
        let meta2 = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var s2 = SessionRecord(id: SessionID(), metadata: meta2)
        s2.append(.userMessage(UserMessage(content: [.text("进度 99% 的 aXb 报告")])))
        try await db.save(s2)
        let hits = try await db.search(query: "50% 的 a_b")
        XCTAssertEqual(hits.count, 1)
        if case let .userMessage(m)? = hits.first?.events.first {
            if case let .text(t)? = m.content.first {
                XCTAssertEqual(t, "进度 50% 的 a_b 报告")
            }
        }
    }

    // MARK: - 项目行持久化（P0.2）

    func testProjectRowRoundTripAndOrdering() async throws {
        let now = Date()
        let rowA = ProjectRow(id: "a", name: "项目A", createdAt: now,
                              archived: false, collapsed: true, sortOrder: 2)
        let rowB = ProjectRow(id: "b", name: "项目B", createdAt: now,
                              archived: false, collapsed: false, sortOrder: 0)
        let rowC = ProjectRow(id: "c", name: "项目C", createdAt: now,
                              archived: true, collapsed: false, sortOrder: 1)
        try await db.saveProjectRow(rowA)
        try await db.saveProjectRow(rowC)
        try await db.saveProjectRow(rowB)

        let rows = try await db.loadProjectRows()
        XCTAssertEqual(rows.map(\.id), ["b", "c", "a"]) // sort_order 升序
        XCTAssertEqual(rows[0].name, "项目B")
        XCTAssertEqual(rows[1].archived, true)
        XCTAssertEqual(rows[2].collapsed, true)
        XCTAssertEqual(rows[2].sortOrder, 2, accuracy: 0.001)
        XCTAssertEqual(rows[0].createdAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testProjectRowUpsertPreservesIDAndCreatedAt() async throws {
        let now = Date()
        let row = ProjectRow(id: "x", name: "原名", createdAt: now,
                             archived: false, collapsed: false, sortOrder: 0)
        try await db.saveProjectRow(row)
        // 重命名 + 归档 + 折叠 + 排序：upsert 不新建行
        var updated = row
        updated.name = "新名"
        updated.archived = true
        updated.collapsed = true
        updated.sortOrder = 5
        try await db.saveProjectRow(updated)

        let rows = try await db.loadProjectRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, "x")
        XCTAssertEqual(rows[0].name, "新名")
        XCTAssertEqual(rows[0].archived, true)
        XCTAssertEqual(rows[0].collapsed, true)
        XCTAssertEqual(rows[0].sortOrder, 5, accuracy: 0.001)
        XCTAssertEqual(rows[0].createdAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001) // created_at 不被 upsert 改写
    }

    func testProjectRowDeleteAndExists() async throws {
        let row = ProjectRow(id: "d", name: "D", createdAt: Date(),
                             archived: false, collapsed: false, sortOrder: 0)
        try await db.saveProjectRow(row)
        let existsBefore = try await db.projectRowExists(id: "d")
        XCTAssertTrue(existsBefore)
        try await db.deleteProjectRow(id: "d")
        let existsAfter = try await db.projectRowExists(id: "d")
        XCTAssertFalse(existsAfter)
        let rows = try await db.loadProjectRows()
        XCTAssertEqual(rows.count, 0)
    }

    // MARK: - 项目行 UUID 值去重（2026-08-26 实机重复项目事件，P2 数据卫生加固）

    /// 平台规范形式 = 系统 uuidString 实际输出（本机 macOS 27 beta / Swift 6.3.3 实测为大写，
    /// 旧平台为小写；测试不硬编码大小写，与 `dedupProjectRowsByUUIDValue` 的平台自适应规则一致）
    private static func canonicalID(_ base: String) -> String {
        UUID(uuidString: base)!.uuidString
    }

    func testDedupCaseVariantRowsKeepsCanonicalForm() {
        let now = Date()
        let base = "771da037-abcd-4ef0-8abc-1234567890ab"
        let canonical = Self.canonicalID(base)
        let variant = (canonical == base) ? base.uppercased() : base
        // 复现事件：同一 UUID 值仅大小写不同、sort_order/created_at 相同（物理排序不确定）
        let rowC = ProjectRow(id: canonical, name: "工作演示", createdAt: now,
                              archived: false, collapsed: false, sortOrder: 0)
        let rowV = ProjectRow(id: variant, name: "工作演示", createdAt: now,
                              archived: false, collapsed: false, sortOrder: 0)
        // 两种输入顺序均保留平台规范形式行
        XCTAssertEqual(SessionDB.dedupProjectRowsByUUIDValue([rowC, rowV]).map(\.id), [canonical])
        XCTAssertEqual(SessionDB.dedupProjectRowsByUUIDValue([rowV, rowC]).map(\.id), [canonical])
    }

    func testDedupNoCanonicalFormKeepsFirstInSortOrder() {
        let now = Date()
        let base = "771da037-abcd-4ef0-8abc-1234567890ab"
        let canonical = Self.canonicalID(base)
        let mixed = "771Da037-AbCd-4eF0-8aBc-1234567890aB"
        // 取两个非规范变体（平台规范形式已被剔除，恒剩 2 个）
        let variants = [base, base.uppercased(), mixed].filter { $0 != canonical }
        XCTAssertEqual(variants.count, 2)
        let v1 = ProjectRow(id: variants[0], name: "A", createdAt: now,
                            archived: false, collapsed: false, sortOrder: 0)
        let v2 = ProjectRow(id: variants[1], name: "A", createdAt: now,
                            archived: false, collapsed: false, sortOrder: 0)
        // 无规范形式行：保留排序最前的一行
        XCTAssertEqual(SessionDB.dedupProjectRowsByUUIDValue([v1, v2]).map(\.id), [v1.id])
        XCTAssertEqual(SessionDB.dedupProjectRowsByUUIDValue([v2, v1]).map(\.id), [v2.id])
    }

    func testDedupDistinctValuesAndNonUUIDIDsUnchanged() {
        let now = Date()
        let r1 = ProjectRow(id: "a", name: "A", createdAt: now,
                            archived: false, collapsed: false, sortOrder: 0) // 非 UUID id，防御性保留
        let r2 = ProjectRow(id: "771da037-abcd-4ef0-8abc-1234567890ab", name: "B", createdAt: now,
                            archived: false, collapsed: false, sortOrder: 1)
        let r3 = ProjectRow(id: "00000000-1111-2222-3333-444444444444", name: "C", createdAt: now,
                            archived: false, collapsed: false, sortOrder: 2)
        let out = SessionDB.dedupProjectRowsByUUIDValue([r1, r2, r3])
        XCTAssertEqual(out.map(\.id), [r1.id, r2.id, r3.id])
    }

    func testLoadProjectRowsDedupesCaseVariantIDs() async throws {
        // DB 级：TEXT 主键下同一 UUID 值大小写变体可共存两行 → loadProjectRows 仅保留平台规范形式行
        let now = Date()
        let base = "771da037-abcd-4ef0-8abc-1234567890ab"
        let canonical = Self.canonicalID(base)
        let variant = (canonical == base) ? base.uppercased() : base
        let a = ProjectRow(id: variant, name: "工作演示", createdAt: now,
                           archived: false, collapsed: false, sortOrder: 0)
        let b = ProjectRow(id: canonical, name: "工作演示", createdAt: now,
                           archived: false, collapsed: false, sortOrder: 0)
        try await db.saveProjectRow(a) // 先插非规范行、后插规范行
        try await db.saveProjectRow(b)
        let rows = try await db.loadProjectRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, canonical) // 保留平台规范形式（会话/持久化共用编码形式）
    }

    // MARK: - v1 → v2 迁移

    func testV1ToV2Migration() async throws {
        // 构造一个只含 v1 schema 的旧库（user_version=1），再经 SessionDB 打开应自动迁移 v2
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-v1-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        let legacy = try DatabaseQueue(path: legacyURL.path)
        try await legacy.write { db in
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
            // GRDB 6 迁移跟踪表（实测真实库 user_version 恒 0，迁移状态记录于此）
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1')")
        }
        let migrated = try SessionDB(dbURL: legacyURL)
        let rows = try await migrated.loadProjectRows()
        XCTAssertEqual(rows.count, 0) // 迁移成功且无项目数据
        let row = ProjectRow(id: "m", name: "迁移后新建", createdAt: Date(),
                             archived: false, collapsed: false, sortOrder: 0)
        try await migrated.saveProjectRow(row)
        let after = try await migrated.loadProjectRows()
        XCTAssertEqual(after.map(\.id), ["m"])
    }

    // MARK: - SessionMetadata 向后兼容（projectId / archived）

    func testMetadataOldJSONDecodesWithoutNewFields() throws {
        let oldJSON = """
        {"cwd":"file:///tmp","createdAt":700000000,"origin":"user","pinned":true}
        """
        let meta = try JSONDecoder().decode(SessionMetadata.self, from: Data(oldJSON.utf8))
        XCTAssertNil(meta.projectId)
        XCTAssertFalse(meta.archived)
        XCTAssertTrue(meta.pinned) // 旧字段不受影响
    }

    func testMetadataProjectFieldsRoundTripThroughDB() async throws {
        let pid = UUID()
        var meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"), projectId: pid, archived: true)
        var session = SessionRecord(id: SessionID(), metadata: meta)
        session.append(.userMessage(UserMessage(content: [.text("项目内会话")])))
        try await db.save(session)

        let loaded = try await db.loadSessions()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(try XCTUnwrap(loaded.first).metadata.projectId, pid)
        XCTAssertEqual(try XCTUnwrap(loaded.first).metadata.archived, true)

        // withProject / withArchived 副本
        meta = meta.withProject(nil).withArchived(false)
        XCTAssertNil(meta.projectId)
        XCTAssertFalse(meta.archived)
        XCTAssertFalse(meta.pinned)
    }
}
