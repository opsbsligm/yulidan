import Foundation

/// 会话存储 — Actor 隔离，保证线程安全
actor SessionStore {
    private var sessions: [SessionID: Session] = [:]
    
    public init() {}
    
    /// 创建新会话
    public func create(metadata: SessionMetadata) -> Session {
        let id = SessionID()
        let session = Session(id: id, metadata: metadata)
        sessions[id] = session
        return session
    }
    
    /// 获取会话
    public func get(_ id: SessionID) -> Session? {
        return sessions[id]
    }
    
    /// 追加事件
    public func append(_ event: SessionEvent, to sessionID: SessionID) {
        sessions[sessionID]?.append(event)
    }
    
    /// 获取所有会话
    public func list() -> [Session] {
        return Array(sessions.values)
    }
    
    /// 删除会话
    public func delete(_ id: SessionID) {
        sessions.removeValue(forKey: id)
    }
    
    /// 从日志推导消息历史
    public func deriveMessages(for sessionID: SessionID) -> [Message]? {
        return sessions[sessionID]?.deriveMessages()
    }
}
