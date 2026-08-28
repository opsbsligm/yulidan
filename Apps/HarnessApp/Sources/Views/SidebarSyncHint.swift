import Account
import SwiftUI

// MARK: - 侧边栏 iCloud 同步状态提示（P2.2.2：同步中/离线/冲突状态指示器）

/// 侧栏底部一眼同步状态提示（纯逻辑，可独立单测）
/// 口径说明（铁律 1）：
/// - 「同步中」引擎未暴露进行中状态（MetadataSyncService 无 publish-in-progress 出口）→ P2 口径简化为
///   在线/离线/连接中三态；冲突裁决 UI 已在 AccountSyncSection.conflictCard，不在此重复
/// - 在线判定源 = NSUbiquitousKeyValueStore.synchronize() 返回值（官方文档：同步尝试是否成功；
///   网络不可达时同步尝试失败返回 false）。轮询周期 30s 为 P2 工程选择
public enum SidebarSyncHint: Equatable {
    /// 本地模式（用户主动选择，无同步预期）：不显示提示，避免噪声
    case hidden
    /// iCloud 启用中 / 在线态尚未取得（激活后首探前的瞬态）
    case connecting
    /// 在线
    case online
    /// 离线（本地优先，网络恢复自动同步）
    case offline
    /// iCloud 不可用，已自动降级本地（reason 供 help 展示）
    case degraded(reason: String)

    /// 状态机映射：工作区状态 + 在线探测 → 提示（纯函数）
    static func resolve(state: WorkspaceState, isOnline: Bool?) -> SidebarSyncHint {
        switch state {
        case .local:
            .hidden
        case .ssoPending:
            .connecting
        case .icloudReady:
            switch isOnline {
            case nil:
                .connecting
            case true:
                .online
            case false:
                .offline
            }
        case let .icloudDegradedLocal(reason):
            .degraded(reason: reason)
        }
    }

    var icon: String {
        switch self {
        case .hidden: ""
        case .connecting: "icloud"
        case .online: "icloud.fill"
        case .offline: "icloud.slash"
        case .degraded: "exclamationmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .hidden: .clear
        case .connecting: .orange
        case .online: .blue
        case .offline: .secondary
        case .degraded: .orange
        }
    }

    var label: String {
        switch self {
        case .hidden: ""
        case .connecting: "iCloud 连接中…"
        case .online: "iCloud 同步：在线"
        case .offline: "iCloud 离线（本地优先）"
        case .degraded: "iCloud 不可用 · 本地模式"
        }
    }

    /// help：状态说明 + 处置引导（点击跳转「账号与同步」子页）
    var help: String {
        switch self {
        case .hidden: ""
        case .connecting: "iCloud 连接中…"
        case .online: "iCloud 同步在线：项目/会话元数据跨设备同步。点击打开「账号与同步」"
        case .offline: "iCloud 当前离线：数据先写本地，网络恢复后自动同步。点击打开「账号与同步」"
        case let .degraded(reason): "iCloud 不可用，已自动降级本地模式：\(reason)。点击打开「账号与同步」重新申请"
        }
    }
}

// MARK: - 视图（展开态行 / 折叠 rail 图标）

/// 展开态底栏同步提示行（点击 → 设置「账号与同步」子页深链）
struct SidebarSyncHintRow: View {
    @ObservedObject var accountService: AccountService
    let onOpenAccount: () -> Void
    @State private var hovered = false

    private var hint: SidebarSyncHint {
        SidebarSyncHint.resolve(state: accountService.state, isOnline: accountService.isOnline)
    }

    var body: some View {
        if hint != .hidden {
            Button(action: onOpenAccount) {
                HStack(spacing: 6) {
                    Image(systemName: hint.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(hint.tint)
                    Text(hint.label)
                        .font(.system(size: 11))
                        .foregroundStyle(hovered ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(hovered ? HarnessTheme.surface : .clear)
                .cornerRadius(5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help(hint.help)
            .padding(.horizontal, 6)
            .accessibilityLabel(hint.label)
        }
    }
}

/// 折叠 rail 同步提示图标（28pt，与 rail 其余按钮同规格；help 携带完整说明）
struct SidebarSyncHintIcon: View {
    @ObservedObject var accountService: AccountService
    let onOpenAccount: () -> Void

    private var hint: SidebarSyncHint {
        SidebarSyncHint.resolve(state: accountService.state, isOnline: accountService.isOnline)
    }

    var body: some View {
        if hint != .hidden {
            Button(action: onOpenAccount) {
                Image(systemName: hint.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(hint.tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.secondary.opacity(0.08)))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(hint.help)
            .accessibilityLabel(hint.label)
        }
    }
}
