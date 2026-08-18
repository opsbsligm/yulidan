import Foundation
import UserNotifications

/// 通知服务抽象 — 生产环境走系统通知中心，测试用 Mock 实现
public protocol NotificationService: Sendable {
    /// 请求通知授权；返回当前是否可用（已授权或刚授予）
    func requestAuthorization() async -> Bool
    /// 投递一条系统通知（identifier 相同时系统会替换旧通知）
    func post(title: String, body: String?, identifier: String?)
}

/// 授权状态抽象（UNNotificationSettings 无法在测试中构造，故抽象为值类型）
public enum AuthorizationState: Sendable {
    case authorized // authorized / provisional / ephemeral 均视为可用
    case notDetermined
    case denied
    case other // @unknown default
}

/// 系统通知中心薄封装（协议化以便测试注入替身；真实实现走 UNUserNotificationCenter）
public protocol NotificationCenterProtocol: Sendable {
    func authorizationStatus() async -> AuthorizationState
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    /// 投递请求（尽力而为，系统 API 的失败不阻塞调用方）
    func add(_ request: UNNotificationRequest)
}

public final class SystemNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func authorizationStatus() async -> AuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .other
        }
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func add(_ request: UNNotificationRequest) {
        try? center.add(request)
    }
}

/// macOS 系统通知实现（UNUserNotificationCenter）
public final class SystemNotificationService: NotificationService, @unchecked Sendable {
    private let center: any NotificationCenterProtocol

    public init(center: any NotificationCenterProtocol = SystemNotificationCenter()) {
        self.center = center
    }

    public func requestAuthorization() async -> Bool {
        do {
            switch await center.authorizationStatus() {
            case .authorized:
                return true
            case .notDetermined:
                return try await center.requestAuthorization(options: [.alert, .sound])
            case .denied, .other:
                return false
            }
        } catch {
            return false
        }
    }

    public func post(title: String, body: String?, identifier: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body {
            content.body = body
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier ?? UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}

/// 通知编排：开关 + 授权门控 + 统一文案。
/// 生成完成 / 失败等事件经此投递，未开启或未授权时静默。
public actor NotificationCoordinator {
    public private(set) var isEnabled: Bool
    private let service: any NotificationService

    public init(service: any NotificationService, isEnabled: Bool = true) {
        self.service = service
        self.isEnabled = isEnabled
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// 主动请求系统授权（用户在设置里开启通知时调用）
    public func ensureAuthorization() async -> Bool {
        await service.requestAuthorization()
    }

    /// 生成完成/失败通知
    public func postGenerationFinished(sessionTitle: String, error: String?) async {
        guard isEnabled else { return }
        guard await service.requestAuthorization() else { return }
        if let error {
            service.post(title: "生成失败", body: "\(sessionTitle)：\(error)", identifier: "harness.generation.failed")
        } else {
            service.post(title: "生成完成", body: sessionTitle, identifier: "harness.generation.finished")
        }
    }

    /// 通用事件通知（子 Agent 完成等）
    public func post(event: String, detail: String?) async {
        guard isEnabled else { return }
        guard await service.requestAuthorization() else { return }
        service.post(title: event, body: detail, identifier: "harness.event")
    }
}
