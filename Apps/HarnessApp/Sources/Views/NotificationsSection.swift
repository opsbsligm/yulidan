import SwiftUI

/// 系统通知设置：开关（AppStorage 持久化）+ 变更回调同步 NotificationCoordinator
struct NotificationsSection: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    var onNotificationsChange: ((Bool) -> Void)?

    var body: some View {
        SettingsCard(title: "通知", icon: "bell.badge") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $notificationsEnabled) {
                    Text("系统通知")
                        .font(.system(.body))
                        .foregroundStyle(HarnessTheme.textPrimary)
                }
                Text("生成完成或失败时发送 macOS 系统通知；首次开启需授权通知权限。")
                    .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
            }
            .onChange(of: notificationsEnabled) { _, newValue in
                onNotificationsChange?(newValue)
            }
        }
    }
}
