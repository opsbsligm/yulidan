import Foundation
@testable import HarnessApp
import Session
import Testing

// MARK: - AppViewModel 会话搜索（临时数据库 + 真实 SessionDB）

@MainActor
@Suite("AppViewModel 会话搜索", .serialized)
struct AppViewModelSessionSearchTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-search-test-\(UUID().uuidString).sqlite")
    }

    /// 轮询等搜索出结果（250ms 防抖 + DB 异步）
    private func waitForResults(_ vm: AppViewModel, timeout: TimeInterval = 6) async -> [SessionRecord]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if vm.searchResults != nil {
                return vm.searchResults
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return vm.searchResults
    }

    /// 轮询等启动加载完成（sessions 含 db 会话）
    private func waitForInitialLoad(_ vm: AppViewModel, _ id: SessionID,
                                    timeout: TimeInterval = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if vm.sessions.contains(where: { $0.id == id }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return vm.sessions.contains(where: { $0.id == id })
    }

    @Test("正文检索命中 + 改名/派生标题并集 + 空查询复位")
    func searchFlow() async throws {
        let dbURL = tempDBURL()
        AppViewModel.sessionDBURLOverride = dbURL
        defer {
            AppViewModel.sessionDBURLOverride = nil
            try? FileManager.default.removeItem(at: dbURL)
        }

        // 预置 DB 会话（正文含唯一词）
        let s1 = SessionID()
        let s2 = SessionID()
        if let directDB = try? SessionDB(dbURL: dbURL) {
            var rec1 = SessionRecord(id: s1, metadata: SessionMetadata(cwd: URL(fileURLWithPath: "/tmp")))
            rec1.append(.userMessage(Session.UserMessage(content: [.text("搜索验证 量子计算 笔记")])))
            var rec2 = SessionRecord(id: s2, metadata: SessionMetadata(cwd: URL(fileURLWithPath: "/tmp")))
            rec2.append(.userMessage(Session.UserMessage(content: [.text("另一个话题 ABC标题词")])))
            try await directDB.save(rec1)
            try await directDB.save(rec2)
        } else {
            Issue.record("临时 SessionDB 打开失败")
            return
        }

        let vm = AppViewModel()
        guard await waitForInitialLoad(vm, s1) else {
            Issue.record("启动加载未完成")
            return
        }

        // 正文检索：量子计算 只在 s1 正文里
        vm.handleSessionSearch("量子计算")
        var results = await waitForResults(vm)
        #expect(results != nil)
        let ids = results?.map(\.id) ?? []
        #expect(ids.contains(s1))
        #expect(!ids.contains(s2))

        // 标题并集：s2 正文无"标题词"以外信息，但派生标题（首条用户消息）含 ABC标题词
        vm.handleSessionSearch("ABC标题词")
        // 先清空上一次结果，再等新结果
        try? await Task.sleep(nanoseconds: 400_000_000)
        results = vm.searchResults
        #expect(results?.contains(where: { $0.id == s2 }) == true)

        // 空查询复位
        vm.handleSessionSearch("")
        #expect(vm.searchResults == nil)
    }

    @Test("无匹配时结果为空数组")
    func noMatch() async {
        let dbURL = tempDBURL()
        AppViewModel.sessionDBURLOverride = dbURL
        defer {
            AppViewModel.sessionDBURLOverride = nil
            try? FileManager.default.removeItem(at: dbURL)
        }
        let vm = AppViewModel()
        vm.handleSessionSearch("绝对不存在的词xyz123")
        let results = await waitForResults(vm)
        #expect(results?.isEmpty == true)
    }
}
