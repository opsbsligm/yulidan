import SwiftUI
import Session

struct ContentView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航
            SidebarView(
                selectedTab: $viewModel.selectedTab,
                selectedSession: $viewModel.selectedSession,
                sessions: viewModel.sessions,
                onNewSession: { viewModel.createNewSession() },
                onSelectSession: { viewModel.selectSession($0) },
                onDeleteSession: { viewModel.deleteSession($0) }
            )

            Divider().frame(width: 1)

            // 主内容区
            mainContent
        }
        .background(HarnessTheme.bgPrimary)
        .frame(minWidth: 800, minHeight: 500)
        // 全局 Toast
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(HarnessTheme.border, lineWidth: 0.5))
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast)
            }
        }
        .animation(.smooth, value: viewModel.toastMessage)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.selectedTab {
        case .chat:
            if let session = viewModel.selectedSession {
                ChatAreaView(session: session, viewModel: viewModel)
            } else {
                WelcomeAreaView(viewModel: viewModel)
            }
        case .plugins:
            PluginListView(viewModel: viewModel)
        case .tools:
            ToolListView(
                tools: $viewModel.tools,
                onExecute: { viewModel.executeTool(at: $0, withParams: $1) },
                onClear: { viewModel.clearToolResult(at: $0) }
            )
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - 应用标签

enum AppTab: CaseIterable, Identifiable {
    case chat, plugins, tools, settings

    var id: String { title }

    var title: String {
        switch self {
        case .chat: return "对话"
        case .plugins: return "插件"
        case .tools: return "工具"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .plugins: return "puzzlepiece.extension"
        case .tools: return "wrench.and.screwdriver"
        case .settings: return "gear"
        }
    }
}

#Preview {
    ContentView()
}
