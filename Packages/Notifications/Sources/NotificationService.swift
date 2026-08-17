import Foundation
import UserNotifications

/// 通知服务抽象 — 生产环境走系统通知中心，测试用 Mock 实现
public protocol NotificationService: Sendable {
    /// 请求通知授权；返回当前是否可用（已授权或刚授予）
    func requestAuthorization() async -> Bool
    /// 投递一条系统通知（identifier 相同时系统会替换旧通知）
    func post(title: String, body: String?, identifier: String?)
}

/// macOS 系统通知实现（UNUserNotificationCenter）
public final class SystemNotificationService: NotificationService, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            case .notDetermined:
                return try await center.requestAuthorization(options: [.alert, .sound])
            case .denied:
                return false
            @unknown default:
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
        try? center.add(request)
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
