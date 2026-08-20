import Account
import SwiftUI

/// 账号与同步（P0.1）：Apple SSO 状态 + 工作区模式切换 + iCloud 降级/重新申请
struct AccountSyncSection: View {
    @ObservedObject var accountService: AccountService

    var body: some View {
        VStack(spacing: 16) {
            accountCard
            workspaceCard
        }
    }

    // MARK: - 账号卡片

    private var accountCard: some View {
        SettingsCard(title: "Apple 账号", icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 10) {
                if let account = accountService.account {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(HarnessTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName ?? account.userID)
                                .font(.system(.body))
                                .foregroundStyle(HarnessTheme.textPrimary)
                            if let email = account.email {
                                Text(email)
                                    .font(.system(size: 12))
                                    .foregroundStyle(HarnessTheme.textSecondary)
                            }
                        }
                    }
                    Button("退出登录", role: .destructive) {
                        accountService.signOut()
                    }
                    .controlSize(.small)
                } else {
                    Text("未登录 Apple ID。登录后可启用 iCloud 跨设备同步。")
                        .font(.system(size: 12))
                        .foregroundStyle(HarnessTheme.textSecondary)
                    Button("使用 Apple 登录") {
                        accountService.signInWithApple()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(accountService.state == .ssoPending)
                }
                if accountService.state == .ssoPending {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在等待 Apple 授权…")
                            .font(.system(size: 12))
                            .foregroundStyle(HarnessTheme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - 工作区模式卡片

    private var workspaceCard: some View {
        SettingsCard(title: "工作区模式", icon: "icloud") {
            VStack(alignment: .leading, spacing: 10) {
                // 当前状态
                HStack(spacing: 8) {
                    statusBadge
                    Text(stateDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textPrimary)
                }
                // 探测详情
                if let probe = accountService.lastProbe {
                    Text(probeDescription(probe))
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                }
                // 降级原因 + 重新申请
                if let reason = accountService.state.degradationReason {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Button("重新申请 iCloud 权限") {
                        accountService.retryICloud()
                    }
                    .controlSize(.small)
                }
                // 登录/探测失败信息（降级态的 reason 已单独展示，不重复）
                if let error = accountService.lastError, error != accountService.state.degradationReason {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.error)
                }
                Divider()
                // 模式切换按钮
                switch accountService.state {
                case .icloudReady:
                    Button("切回离线本地模式") {
                        accountService.switchToLocalMode()
                    }
                    .controlSize(.small)
                case .local, .icloudDegradedLocal:
                    Button("启用 Apple SSO + iCloud 同步") {
                        if accountService.account != nil {
                            accountService.retryICloud()
                        } else {
                            accountService.signInWithApple()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                case .ssoPending:
                    EmptyView()
                }
                if let online = accountService.isOnline {
                    Text(online ? "iCloud 同步：在线" : "iCloud 同步：离线（本地优先，联网后自动同步）")
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                }
            }
        }
    }

    // MARK: - 组件

    private var statusBadge: some View {
        let (icon, color): (String, Color) = switch accountService.state {
        case .icloudReady: ("icloud.fill", .blue)
        case .local: ("internaldrive", .secondary)
        case .ssoPending: ("arrow.triangle.2.circlepath", .orange)
        case .icloudDegradedLocal: ("exclamationmark.icloud", .orange)
        }
        return Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(color)
    }

    private var stateDescription: String {
        switch accountService.state {
        case .local:
            "离线本地模式：数据仅存本机磁盘"
        case .ssoPending:
            "SSO 流程进行中"
        case .icloudReady:
            "Apple SSO + iCloud 同步模式"
        case .icloudDegradedLocal:
            "iCloud 不可用，已自动降级为本地模式"
        }
    }

    private func probeDescription(_ probe: ICloudProbe) -> String {
        let accountText = probe.hasICloudAccount ? "设备已登录 iCloud" : "设备未登录 iCloud"
        if let url = probe.containerURL {
            return "\(accountText) · 容器：\(url.lastPathComponent)"
        }
        return "\(accountText) · 容器不可用"
    }
}
