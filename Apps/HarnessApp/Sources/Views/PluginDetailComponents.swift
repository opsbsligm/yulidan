import ServiceContainer
import SwiftUI

// MARK: - 插件详情辅助组件（自 PluginListView 拆分：file_length 门禁）

struct StateBadge: View {
    let state: PluginState
    var color: Color {
        switch state {
        case .active: .green
        case .stopped: .gray
        case .failed, .errored: .red
        case .loading, .initializing, .starting, .stopping: .orange
        }
    }

    var label: String {
        switch state {
        case .active: "运行中"
        case .stopped: "已停用"
        case .failed: "失败"
        case .errored: "错误"
        case .loading: "加载中"
        case .initializing: "初始化"
        case .starting: "启动中"
        case .stopping: "停止中"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11)).foregroundStyle(color)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(HarnessTheme.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced))
        }
    }
}
