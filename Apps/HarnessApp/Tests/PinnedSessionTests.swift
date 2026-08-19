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
