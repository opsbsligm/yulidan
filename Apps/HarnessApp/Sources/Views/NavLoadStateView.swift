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
