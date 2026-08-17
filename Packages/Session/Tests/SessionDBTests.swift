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
}
