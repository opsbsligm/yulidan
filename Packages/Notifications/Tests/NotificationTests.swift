import Foundation
@testable import Notifications
import Testing

/// Mock 通知服务：记录授权与投递行为
private final class MockNotificationService: NotificationService, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorized: Bool
    private var _postLog: [(title: String, body: String?, identifier: String?)] = []
    private var _authRequests = 0

    init(authorized: Bool = true) {
        _authorized = authorized
    }

    var postLog: [(title: String, body: String?, identifier: String?)] {
        lock.withLock { _postLog }
    }

    var authRequestCount: Int {
        lock.withLock { _authRequests }
    }

    func requestAuthorization() async -> Bool {
        lock.withLock { _authRequests += 1; return _authorized }
    }

    func post(title: String, body: String?, identifier: String?) {
        lock.withLock { _postLog.append((title, body, identifier)) }
    }
}

@Suite("NotificationCoordinator Tests")
struct NotificationCoordinatorTests {
    @Test("Disabled coordinator posts nothing")
    func disabled() async {
        let service = MockNotificationService()
        let coordinator = NotificationCoordinator(service: service, isEnabled: false)
        await coordinator.postGenerationFinished(sessionTitle: "测试会话", error: nil)
        #expect(service.postLog.isEmpty)
        #expect(service.authRequestCount == 0)
    }

    @Test("Denied authorization posts nothing")
    func denied() async {
        let service = MockNotificationService(authorized: false)
        let coordinator = NotificationCoordinator(service: service)
        await coordinator.postGenerationFinished(sessionTitle: "测试会话", error: nil)
        #expect(service.postLog.isEmpty)
        #expect(service.authRequestCount == 1)
    }

    @Test("Success posts generation finished")
    func success() async {
        let service = MockNotificationService()
        let coordinator = NotificationCoordinator(service: service)
        await coordinator.postGenerationFinished(sessionTitle: "修复登录 bug", error: nil)
        #expect(service.postLog.count == 1)
        #expect(service.postLog[0].title == "生成完成")
        #expect(service.postLog[0].body == "修复登录 bug")
        #expect(service.postLog[0].identifier == "harness.generation.finished")
    }

    @Test("Failure posts generation failed with reason")
    func failure() async {
        let service = MockNotificationService()
        let coordinator = NotificationCoordinator(service: service)
        await coordinator.postGenerationFinished(sessionTitle: "测试会话", error: "网络超时")
        #expect(service.postLog.count == 1)
        #expect(service.postLog[0].title == "生成失败")
        #expect(service.postLog[0].body == "测试会话：网络超时")
        #expect(service.postLog[0].identifier == "harness.generation.failed")
    }

    @Test("Toggle at runtime changes behavior")
    func toggle() async {
        let service = MockNotificationService()
        let coordinator = NotificationCoordinator(service: service)
        await coordinator.postGenerationFinished(sessionTitle: "A", error: nil)
        #expect(service.postLog.count == 1)

        await coordinator.setEnabled(false)
        await coordinator.post(event: "子 Agent 完成", detail: "任务 X")
        #expect(service.postLog.count == 1)

        await coordinator.setEnabled(true)
        await coordinator.post(event: "子 Agent 完成", detail: "任务 Y")
        #expect(service.postLog.count == 2)
        #expect(service.postLog[1].title == "子 Agent 完成")
        #expect(service.postLog[1].body == "任务 Y")
    }
}
