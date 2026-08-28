import Account
import SwiftUI

/// 账号与同步（P0.1）：Apple SSO 状态 + 工作区模式切换 + iCloud 降级/重新申请
/// P0.1.4：多设备同步冲突 → 待裁决列表（用户选择保留本地/云端版本）
struct AccountSyncSection: View {
    @ObservedObject var accountService: AccountService
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            if !viewModel.pendingSyncConflicts.isEmpty {
                conflictCard
            }
            accountCard
            workspaceCard
        }
    }

    // MARK: - 同步冲突裁决卡（P0.1.4）

    private var conflictCard: some View {
        SettingsCard(title: "同步冲突（需裁决）", icon: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("以下数据在多台设备上同时修改，请逐项选择保留版本：")
                    .font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.textSecondary)
                ForEach(viewModel.pendingSyncConflicts) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.keyDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HarnessTheme.textPrimary)
                        VStack(alignment: .leading, spacing: 4) {
                            syncSideLabel("本地", item.localPreview)
                            syncSideLabel("云端", item.remotePreview)
                        }
                        HStack(spacing: 8) {
                            Button("保留本地") {
                                viewModel.resolveSyncConflict(id: item.id, keepLocal: true)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button("保留云端") {
                                viewModel.resolveSyncConflict(id: item.id, keepLocal: false)
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(HarnessTheme.surfaceHover)
                    .cornerRadius(8)
                }
            }
        }
    }

    private func syncSideLabel(_ side: String, _ preview: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(side)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HarnessTheme.textTertiary)
                .frame(width: 30, alignment: .leading)
            Text(preview.isEmpty ? "（空）" : preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HarnessTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
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
                    Text("未登录 Apple ID（可选）。SSO 是应用层身份，iCloud 同步不依赖它。")
                        .font(.system(size: 12))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("使用 Apple 登录") {
                        accountService.signInWithApple()
                    }
                    .buttonStyle(.glassProminent) // P1.1 C5：Apple 登录（主操作）→ 玻璃强调
                    .controlSize(.small)
                    .disabled(accountService.state == .ssoPending)
                    Text("需付费 Apple 开发者 Team + Sign in with Apple 能力；当前 ad-hoc 构建不可用。")
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Button("启用 iCloud 跨设备同步") {
                        accountService.retryICloud()
                    }
                    .buttonStyle(.glassProminent) // P1.1 C5：启用 iCloud（主操作）→ 玻璃强调
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
            "iCloud 同步模式（跨设备）"
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
