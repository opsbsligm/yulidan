import XCTest
import GRDB
@testable import Session

/// SessionDB 持久化测试：save / loadAll / delete 往返
final class SessionDBTests: XCTestCase {
    private var dbURL: URL!
    private var db: SessionDB!

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
        var session = Session(id: SessionID(), metadata: meta)
        session.append(.userMessage(UserMessage(content: [.text("你好，Harness")])))
        session.append(.assistantMessage(AssistantMessage(
            turn: 1, step: 0, content: [.text("你好！有什么可以帮你？")],
            provider: "deepseek", model: "deepseek-chat")))
        session.currentTurn = 1
        try await db.save(session)

        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, session.id)
        XCTAssertEqual(loaded[0].currentTurn, 1)
        XCTAssertEqual(loaded[0].events.count, 2)
        if case .userMessage(let m) = loaded[0].events.first! {
            if case .text(let t) = m.content.first! {
                XCTAssertEqual(t, "你好，Harness")
            } else { XCTFail("expected text block") }
        }
    }

    func testUpsertRewritesEvents() async throws {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        var session = Session(id: SessionID(), metadata: meta)
        session.append(.userMessage(UserMessage(content: [.text("第一条")])))
        try await db.save(session)

        session.append(.userMessage(UserMessage(content: [.text("第二条")])))
        try await db.save(session)

        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded[0].events.count, 2)
    }

    func testDelete() async throws {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        let session = Session(id: SessionID(), metadata: meta)
        try await db.save(session)
        try await db.delete(session.id)
        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded.count, 0)
    }

    func testMultipleSessionsOrdered() async throws {
        let m1 = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"), createdAt: Date().addingTimeInterval(-100))
        let m2 = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"), createdAt: Date())
        try await db.save(Session(id: SessionID(), metadata: m1))
        try await db.save(Session(id: SessionID(), metadata: m2))
        let loaded = try await db.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertGreaterThan(loaded[0].metadata.createdAt, loaded[1].metadata.createdAt)
    }
}
