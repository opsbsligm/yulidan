import Foundation
@testable import Notifications
import Testing
import UserNotifications

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

// MARK: - SystemNotificationService（FakeCenter 注入，不触达真实通知中心）

private final class FakeNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let state: AuthorizationState
    private let requestResult: Bool
    private let throwOnRequest: Bool
    private var _requestCalls = 0
    private var _added: [UNNotificationRequest] = []
    private var _requestOptions: [UNAuthorizationOptions] = []

    init(state: AuthorizationState, requestResult: Bool = false, throwOnRequest: Bool = false) {
        self.state = state
        self.requestResult = requestResult
        self.throwOnRequest = throwOnRequest
    }

    var requestCalls: Int {
        lock.withLock { _requestCalls }
    }

    var requestOptions: [UNAuthorizationOptions] {
        lock.withLock { _requestOptions }
    }

    var added: [UNNotificationRequest] {
        lock.withLock { _added }
    }

    func authorizationStatus() async -> AuthorizationState {
        state
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.withLock { _requestCalls += 1; _requestOptions.append(options) }
        if throwOnRequest {
            throw NSError(domain: "FakeCenter", code: 7)
        }
        return requestResult
    }

    func add(_ request: UNNotificationRequest) {
        lock.withLock { _added.append(request) }
    }
}

@Suite("SystemNotificationService Tests")
struct SystemNotificationServiceTests {
    private func makeService(_ state: AuthorizationState, requestResult: Bool = false, throwError: Bool = false)
        -> (SystemNotificationService, FakeNotificationCenter) {
        let center = FakeNotificationCenter(state: state, requestResult: requestResult, throwOnRequest: throwError)
        return (SystemNotificationService(center: center), center)
    }

    @Test("已授权状态直接可用，不重复请求")
    func alreadyAuthorized() async {
        let (service, center) = makeService(.authorized)
        #expect(await service.requestAuthorization() == true)
        #expect(center.requestCalls == 0)
    }

    @Test("notDetermined 时发起系统请求并返回结果")
    func notDeterminedRequests() async {
        let (granted, center) = makeService(.notDetermined, requestResult: true)
        #expect(await granted.requestAuthorization() == true)
        #expect(center.requestCalls == 1)
        #expect(center.requestOptions[0].contains(.alert))
        #expect(center.requestOptions[0].contains(.sound))

        let (refused, _) = makeService(.notDetermined, requestResult: false)
        #expect(await refused.requestAuthorization() == false)
    }

    @Test("denied 状态返回不可用且不请求")
    func denied() async {
        let (service, center) = makeService(.denied, requestResult: true)
        #expect(await service.requestAuthorization() == false)
        #expect(center.requestCalls == 0)
    }

    @Test("未知状态（other）返回不可用且不请求")
    func otherState() async {
        let (service, center) = makeService(.other, requestResult: true)
        #expect(await service.requestAuthorization() == false)
        #expect(center.requestCalls == 0)
    }

    @Test("请求系统授权抛错时返回不可用（catch 分支）")
    func requestThrows() async {
        let (service, center) = makeService(.notDetermined, throwError: true)
        #expect(await service.requestAuthorization() == false)
        #expect(center.requestCalls == 1)
    }

    @Test("post 携带 body 与指定 identifier")
    func postWithBodyAndIdentifier() {
        let (service, center) = makeService(.authorized)
        service.post(title: "生成完成", body: "会话 A", identifier: "harness.generation.finished")
        #expect(center.added.count == 1)
        let req = center.added[0]
        #expect(req.identifier == "harness.generation.finished")
        #expect(req.content.title == "生成完成")
        #expect(req.content.body == "会话 A")
        #expect(req.content.sound == .default)
    }

    @Test("post 无 body 时正文为空串")
    func postWithoutBody() {
        let (service, center) = makeService(.authorized)
        service.post(title: "提醒", body: nil, identifier: "x")
        #expect(center.added.count == 1)
        #expect(center.added[0].content.body.isEmpty)
    }

    @Test("post 无 identifier 时自动生成 UUID")
    func postGeneratesUUIDWhenIdentifierNil() {
        let (service, center) = makeService(.authorized)
        service.post(title: "提醒", body: "b", identifier: nil)
        #expect(center.added.count == 1)
        let id = center.added[0].identifier
        #expect(!id.isEmpty)
        #expect(UUID(uuidString: id) != nil)
    }
}
