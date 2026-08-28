import SwiftUI

// MARK: - 导航 Tab 加载状态组件（P0.3 异常 UI：加载中 / 已加载 / 加载失败）

/// 加载中占位：替换列表空态，避免加载窗口内"空数据"闪烁误导
struct NavLoadingView: View {
    var text: String = "加载中…"

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(HarnessTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

/// 加载失败横幅：列表仍渲染已加载的部分内容，重试按钮重跑对应加载链路
struct NavErrorBanner: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(HarnessTheme.error)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HarnessTheme.error)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button("重试", action: onRetry)
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(HarnessTheme.error.opacity(0.08))
    }
}

// MARK: - P0.4 插件权限裁决横幅（授予 / 拒绝）

struct NavPermissionBanner: View {
    let name: String
    let version: String
    let permissions: [String]
    var onGrant: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13))
                    .foregroundStyle(HarnessTheme.accent)
                Text("插件「\(name)」v\(version) 正在请求以下权限：")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
            }
            HStack(spacing: 6) {
                ForEach(permissions, id: \.self) { perm in
                    Text(perm)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(HarnessTheme.accent.opacity(0.12))
                        .foregroundStyle(HarnessTheme.accent)
                        .clipShape(Capsule())
                }
            }
            HStack {
                Spacer()
                Button("拒绝", action: onDeny)
                    .font(.system(size: 12))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("授予并安装", action: onGrant)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.glassProminent) // P1.1 C5：授予并安装（主操作）→ 玻璃强调
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(HarnessTheme.accent.opacity(0.06))
    }
}

/// 部分失败警告横幅（橙色）：列表仍渲染已加载内容（如个别 MCP 服务器连接失败）
struct NavWarningBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(HarnessTheme.warning)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HarnessTheme.warning)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(HarnessTheme.warning.opacity(0.08))
    }
}
