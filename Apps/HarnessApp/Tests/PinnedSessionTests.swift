import Foundation
@testable import HarnessApp
import Session
import Testing

// MARK: - F9：置顶会话（B6：metadata 持久化 + 列表置顶段数据源）

@MainActor
@Suite("F9 置顶会话", .serialized)
struct PinnedSessionTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-pin-test-\(UUID().uuidString).sqlite")
    }

    private func tempSkillDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-pin-skills-\(UUID().uuidString)")
    }

    @Test("置顶/取消置顶：sessions 数组更新 + DB 持久化往返")
    func togglePinPersists() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempSkillDir()
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        vm.createNewSession(silent: true)
        let session = vm.sessions[0]
        #expect(!session.metadata.pinned)

        // 置顶 → 数组更新
        vm.togglePinSession(session)
        #expect(vm.sessions[0].metadata.pinned)
        #expect(vm.selectedSession?.metadata.pinned == true)

        // DB 异步落盘：轮询直到持久化可见
        guard let db = vm.sessionDB else {
            Issue.record("sessionDB 应为非 nil")
            return
        }
        let d0 = Date().addingTimeInterval(10)
        var loadedPinned: Bool?
        while Date() < d0, loadedPinned == nil {
            loadedPinned = await (try? db.load(session.id))?.metadata.pinned
            if loadedPinned == nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        #expect(loadedPinned == true, "置顶态应持久化到 DB")

        // 取消置顶 → 持久化回 false
        vm.togglePinSession(vm.sessions[0])
        #expect(!vm.sessions[0].metadata.pinned)
        let d1 = Date().addingTimeInterval(10)
        var loadedUnpinned: Bool?
        while Date() < d1, loadedUnpinned != false {
            loadedUnpinned = await (try? db.load(session.id))?.metadata.pinned
            if loadedUnpinned != false {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        #expect(loadedUnpinned == false, "取消置顶应持久化回 false")
    }
}

// MARK: - SessionGroups 分组纯函数（置顶段最顶 + 日分组 + 组内倒序）

@Suite("SessionGroups 分组纯函数")
struct SessionGroupsTests {
    private var now: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 18; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    private func record(daysAgo: Int, hourOffset: Double = 0, pinned: Bool = false) -> SessionRecord {
        let createdAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
            .addingTimeInterval(hourOffset)
        return SessionRecord(metadata: SessionMetadata(cwd: URL(fileURLWithPath: "/tmp"),
                                                       createdAt: createdAt,
                                                       origin: .user,
                                                       pinned: pinned))
    }

    @Test("置顶段在最顶；置顶项不重复出现在日分组")
    func pinnedGroupFirst() {
        let pinnedOld = record(daysAgo: 5, pinned: true) // 旧会话置顶
        let today1 = record(daysAgo: 0, hourOffset: -3600)
        let today2 = record(daysAgo: 0, hourOffset: -1800)
        let groups = SessionGroups.group([today1, pinnedOld, today2], now: now)
        #expect(groups.count == 2)
        #expect(groups[0].label == "置顶")
        #expect(groups[0].items.map(\.id) == [pinnedOld.id])
        #expect(groups[1].label == "今天")
        // 组内创建时间倒序（today2 更新）
        #expect(groups[1].items.map(\.id) == [today2.id, today1.id])
        // 置顶项不得重复出现在「今天/昨天/更早」
        let all = groups.flatMap { $0.items.map(\.id) }
        #expect(all.filter { $0 == pinnedOld.id }.count == 1)
    }

    @Test("今天/昨天/更早 分段；空输入返回空")
    func dailyBucketsAndEmpty() {
        let today = record(daysAgo: 0)
        let yesterday = record(daysAgo: 1)
        let earlier = record(daysAgo: 10)
        let groups = SessionGroups.group([earlier, today, yesterday], now: now)
        #expect(groups.map(\.label) == ["今天", "昨天", "更早"])
        #expect(SessionGroups.group([], now: now).isEmpty)
    }
}
