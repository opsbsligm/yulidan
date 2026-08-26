import Foundation
import Session
import SQLite3
import Testing

// MARK: - 覆盖审计轮 17：SessionMetadata 旧版解码兜底 + SessionDB 脏行 mapRow 兜底

@Suite("Session R17 Gap Coverage")
struct SessionR17GapTests {
    /// ① 旧版 metadata_json（缺 createdAt/origin/pinned/archived）
    ///    → decodeIfPresent 全部走 `??` 兜底（既有测试 JSON 恒含全部字段，兜底闭包 0 执行）
    @Test("SessionMetadata: 旧版 JSON 缺字段 → 解码兜底（origin=.user 等）")
    func legacyMetadataDecodeFallbacks() throws {
        let projectId = UUID().uuidString
        // 注：forkedFrom 为 SessionID?（合成 Codable 期望对象编码），旧版字符串形式不可解码，
        // 故旧版场景 = 完全缺该字段 → decodeIfPresent nil → nil 兜底
        let json = """
        {"cwd":"file:///tmp/harness-legacy","projectId":"\(projectId)","pinned":true}
        """
        let meta = try JSONDecoder().decode(SessionMetadata.self, from: Data(json.utf8))
        #expect(meta.pinned)
        #expect(meta.origin == .user) // 缺 origin → .user 兜底
        #expect(meta.archived == false) // 缺 archived → false 兜底
        #expect(meta.createdAt != Date.distantPast) // 缺 createdAt → Date() 兜底
        #expect(meta.forkedFrom == nil) // 缺 forkedFrom → nil 兜底
        #expect(meta.projectId?.uuidString == projectId)
    }

    /// ② sqlite3 直接注入脏行（非法 UUID id + 非法 status 字符串）
    ///    → mapRow 两处 `??` 兜底闭包命中（经公共 API 写入的行 id/status 恒合法，兜底 0 执行）
    @Test("SessionDB: 脏行（非法 UUID id + 非法 status）→ mapRow 兜底闭包")
    func garbageRowHitsMapRowFallbacks() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-r17-sessiondb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("sessions.sqlite")

        let db = try SessionDB(dbURL: dbURL)
        // 先经公共 API 保存一条正常会话（建表 + 迁移）
        let normal = SessionRecord(
            metadata: SessionMetadata(cwd: URL(fileURLWithPath: "/tmp/harness-r17"))
        )
        try await db.save(normal)

        // sqlite3 C API 直接注入脏行（id 非 UUID 格式；status 非枚举值）
        var ptr: OpaquePointer?
        let rc = sqlite3_open(dbURL.path, &ptr)
        #expect(rc == SQLITE_OK)
        defer { sqlite3_close(ptr) }
        let metaJSON = "{\"cwd\":\"file:///tmp/harness-r17\",\"createdAt\":0,\"origin\":\"user\"}"
        let sql = "INSERT INTO sessions (id, metadata_json, turn, status, created_at) VALUES ('garbage-not-uuid', '\(metaJSON)', 0, 'bogus-status', 0.5);"
        var errMsg: UnsafeMutablePointer<CChar>?
        let r2 = sqlite3_exec(ptr, sql, nil, nil, &errMsg)
        if r2 != SQLITE_OK {
            Issue.record("sqlite 注入失败：\(errMsg.map { String(cString: $0) } ?? "?")")
        }

        // loadSessions → mapRow 处理脏行：UUID(uuidString:) ?? UUID() 与 SessionStatus(rawValue:) ?? .active 命中
        let list = try await db.loadSessions()
        #expect(list.count == 2)
        let garbage = list.first { $0.metadata.cwd.path == "/tmp/harness-r17" && $0.currentTurn == 0 }
        #expect(garbage != nil, "脏行应被 mapRow 兜底保留（metadata 合法 → 不跳过）")
    }
}
