import Foundation
@testable import ServiceContainer
@testable import Session
import Testing

@Suite("SessionID Tests")
struct SessionIDTests {
    @Test("Generate unique IDs")
    func uniqueIDs() {
        let id1 = SessionID()
        let id2 = SessionID()
        #expect(id1.rawValue != id2.rawValue)
    }

    @Test("Hashable conformance")
    func hashable() {
        let id1 = SessionID()
        let id2 = id1
        #expect(id1 == id2)
        #expect(id1.hashValue == id2.hashValue)
    }
}

@Suite("SessionEvent Tests")
struct SessionEventTests {
    @Test("Turn start event")
    func testTurnStart() {
        let event = SessionEvent.turnStart(turn: 1)
        #expect(event.eventType == "turn/start")
    }

    @Test("Turn end event")
    func testTurnEnd() {
        let event = SessionEvent.turnEnd(turn: 1, reason: .completed)
        #expect(event.eventType == "turn/end")
    }

    @Test("User message event")
    func testUserMessage() {
        let msg = UserMessage(content: [.text("Hello")])
        let event = SessionEvent.userMessage(msg)
        #expect(event.eventType == "user/message")
    }

    @Test("Step start/end events")
    func stepEvents() {
        let start = SessionEvent.stepStart(turn: 1, step: 1)
        let end = SessionEvent.stepEnd(turn: 1, step: 1)
        #expect(start.eventType == "step/start")
        #expect(end.eventType == "step/end")
    }

    @Test("Todo write event")
    func testTodoWrite() {
        let todos: [TodoItem] = []
        let event = SessionEvent.todoWrite(todos)
        #expect(event.eventType == "todo/write")
    }
}

@Suite("UserMessage Tests")
struct UserMessageTests {
    @Test("Initialize message")
    func initMessage() {
        let msg = UserMessage(content: [.text("Hello")])
        #expect(msg.content.count == 1)
        #expect(msg.source.kind == "user")
    }
}

@Suite("ContentBlock Tests")
struct ContentBlockTests {
    @Test("Text block")
    func textBlock() {
        let block: ContentBlock = .text("Hello")
        switch block {
        case let .text(text):
            #expect(text == "Hello")
        default:
            Issue.record("Expected text block")
        }
    }

    @Test("Reasoning block")
    func reasoningBlock() {
        let block: ContentBlock = .reasoning("Thinking...")
        switch block {
        case let .reasoning(text):
            #expect(text == "Thinking...")
        default:
            Issue.record("Expected reasoning block")
        }
    }
}

@Suite("SessionStore Tests")
struct SessionStoreTests {
    @Test("Create session")
    func testCreate() async {
        let store = SessionStore()
        let metadata = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp/test"))
        let session = await store.create(metadata: metadata)

        #expect(session.id.rawValue != UUID())
        #expect(session.events.isEmpty)
        #expect(session.currentTurn == 0)
        #expect(session.status == .active)
    }

    @Test("Get session")
    func testGet() async {
        let store = SessionStore()
        let metadata = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp/test"))
        let session = await store.create(metadata: metadata)

        let retrieved = await store.get(session.id)
        #expect(retrieved != nil)
        #expect(retrieved?.id == session.id)
    }

    @Test("Append event")
    func testAppend() async {
        let store = SessionStore()
        let metadata = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp/test"))
        let session = await store.create(metadata: metadata)

        await store.append(.turnStart(turn: 1), to: session.id)

        let updated = await store.get(session.id)
        #expect(updated?.events.count == 1)
    }

    @Test("List sessions")
    func testList() async {
        let store = SessionStore()
        let metadata = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp/test"))
        _ = await store.create(metadata: metadata)
        _ = await store.create(metadata: metadata)

        let sessions = await store.list()
        #expect(sessions.count == 2)
    }

    @Test("Delete session")
    func testDelete() async {
        let store = SessionStore()
        let metadata = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp/test"))
        let session = await store.create(metadata: metadata)

        await store.delete(session.id)
        #expect(await store.get(session.id) == nil)
    }

    @Test("Derive messages from log")
    func testDeriveMessages() async {
        let store = SessionStore()
        let metadata = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp/test"))
        let session = await store.create(metadata: metadata)

        let userMsg = UserMessage(content: [.text("Hello")])
        await store.append(.userMessage(userMsg), to: session.id)

        let assistantMsg = AssistantMessage(
            turn: 1, step: 1,
            content: [.text("Hi there!")],
            provider: "test", model: "test"
        )
        await store.append(.assistantMessage(assistantMsg), to: session.id)

        let messages = await store.deriveMessages(for: session.id)
        #expect(messages?.count == 2)
    }
}

@Suite("SessionOrigin Tests")
struct SessionOriginTests {
    @Test("All cases have rawValue")
    func rawValues() {
        #expect(SessionOrigin.user.rawValue == "user")
        #expect(SessionOrigin.plugin.rawValue == "plugin")
        #expect(SessionOrigin.forked.rawValue == "forked")
        #expect(SessionOrigin.resumed.rawValue == "resumed")
    }
}

// MARK: - SessionMetadata pinned 字段（Codex 式置顶；旧 JSON 向后兼容）

@Suite("SessionMetadata Pinned Tests")
struct SessionMetadataPinnedTests {
    @Test("缺省 pinned=false；withPinned 切换往返")
    func defaultAndToggle() {
        let meta = SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"))
        #expect(!meta.pinned)
        let pinned = meta.withPinned(true)
        #expect(pinned.pinned)
        #expect(pinned.cwd == meta.cwd)
        #expect(pinned.createdAt == meta.createdAt)
        #expect(!meta.withPinned(true).withPinned(false).pinned)
    }

    @Test("旧 metadata_json（无 pinned 字段）解码为 false，编码后包含 pinned")
    func legacyJSONDecodesAndEncodeIncludesPinned() throws {
        let legacy = """
        {"cwd":"file:///tmp/x","createdAt":780000000,"origin":"user"}
        """
        let decoded = try JSONDecoder().decode(SessionMetadata.self, from: #require(legacy.data(using: .utf8)))
        #expect(!decoded.pinned)
        #expect(decoded.origin == .user)

        let encoded = try JSONEncoder().encode(decoded.withPinned(true))
        let round = try JSONDecoder().decode(SessionMetadata.self, from: encoded)
        #expect(round.pinned)

        // 显式 pinned=false 的旧数据
        let legacyFalse = """
        {"cwd":"file:///tmp/x","createdAt":780000000,"origin":"user","pinned":false}
        """
        let decodedFalse = try JSONDecoder().decode(SessionMetadata.self, from: #require(legacyFalse.data(using: .utf8)))
        #expect(!decodedFalse.pinned)
    }
}
