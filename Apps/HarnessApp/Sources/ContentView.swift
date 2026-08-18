import Session
import SwiftUI

struct ContentView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航
            SidebarView(
                selectedTab: $viewModel.selectedTab,
                selectedSession: $viewModel.selectedSession,
                sessions: viewModel.sessions,
                titleFor: { viewModel.sessionTitle(for: $0) },
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
        case .agents:
            SubagentView(viewModel: viewModel)
        case .plugins:
            PluginListView(viewModel: viewModel)
        case .skills:
            SkillView(viewModel: viewModel)
        case .tools:
            ToolListView(
                tools: $viewModel.tools,
                onExecute: { viewModel.executeTool(at: $0, withParams: $1) },
                onClear: { viewModel.clearToolResult(at: $0) }
            )
        case .settings:
            SettingsView(onSandboxChange: { viewModel.setSandboxRoot($0) },
                         onNotificationsChange: { viewModel.setNotificationsEnabled($0) })
        }
    }
}

// MARK: - 应用标签

enum AppTab: CaseIterable, Identifiable {
    case chat, agents, plugins, skills, tools, settings

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .chat: "对话"
        case .agents: "多Agent"
        case .plugins: "插件"
        case .skills: "技能"
        case .tools: "工具"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .agents: "person.3"
        case .plugins: "puzzlepiece.extension"
        case .skills: "book"
        case .tools: "wrench.and.screwdriver"
        case .settings: "gear"
        }
    }
}

#Preview {
    ContentView()
}
