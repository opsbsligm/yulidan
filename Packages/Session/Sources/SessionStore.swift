import Foundation

/// 会话存储 — Actor 隔离，保证线程安全
actor SessionStore {
    private var sessions: [SessionID: SessionRecord] = [:]

    init() {}

    /// 创建新会话
    func create(metadata: SessionMetadata) -> SessionRecord {
        let id = SessionID()
        let session = SessionRecord(id: id, metadata: metadata)
        sessions[id] = session
        return session
    }

    /// 获取会话
    func get(_ id: SessionID) -> SessionRecord? {
        sessions[id]
    }

    /// 追加事件
    func append(_ event: SessionEvent, to sessionID: SessionID) {
        sessions[sessionID]?.append(event)
    }

    /// 获取所有会话
    func list() -> [SessionRecord] {
        Array(sessions.values)
    }

    /// 删除会话
    func delete(_ id: SessionID) {
        sessions.removeValue(forKey: id)
    }

    /// 从日志推导消息历史
    func deriveMessages(for sessionID: SessionID) -> [Message]? {
        sessions[sessionID]?.deriveMessages()
    }
}
