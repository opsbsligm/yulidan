import Session
import SwiftUI

struct ContentView: View {
    /// ⚠️ 必须 @StateObject（非 @State）：AppViewModel 是 ObservableObject，
    /// @State 不订阅 objectWillChange，异步加载 sessions 后根视图不重算 body，
    /// 侧边栏会话列表将永远停留在启动时的空状态（2026-08-20 实机验收发现，P0）
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航
            SidebarView(
                selectedTab: $viewModel.selectedTab,
                selectedSession: $viewModel.selectedSession,
                sessions: viewModel.searchResults ?? viewModel.sessions,
                projects: viewModel.projects,
                isSearching: viewModel.searchResults != nil,
                searchProjectScope: viewModel.searchProjectScope,
                generatingSessionId: viewModel.generatingSessionId,
                isCollapsed: viewModel.isSidebarCollapsed,
                onToggleCollapse: {
                    withAnimation(.smooth(duration: 0.18)) { viewModel.isSidebarCollapsed.toggle() }
                },
                titleFor: { viewModel.sessionTitle(for: $0) },
                onNewSession: { viewModel.createNewSession() },
                onSelectSession: { viewModel.selectSession($0) },
                onTogglePin: { viewModel.togglePinSession($0) },
                onDeleteSession: { viewModel.deleteSession($0) },
                onSearch: { viewModel.handleSessionSearch($0) },
                onSearchScope: { viewModel.setSearchProjectScope($0) },
                onCreateProject: { viewModel.createProject(name: $0) },
                onRenameProject: { viewModel.renameProject($0, to: $1) },
                onDeleteProject: { viewModel.deleteProject($0, option: $1) },
                onToggleProjectArchived: { viewModel.toggleProjectArchived($0) },
                onToggleProjectCollapsed: { viewModel.toggleProjectCollapsed($0) },
                onMoveSession: { viewModel.moveSession($0, to: $1) },
                onToggleSessionArchived: { viewModel.toggleSessionArchived($0) },
                onUnarchiveProject: { viewModel.unarchiveProject($0) },
                onUnarchiveSession: { viewModel.unarchiveSession($0) },
                sessionsLoadState: viewModel.sessionsLoadState,
                onRetryLoadSessions: { Task { await viewModel.retryLoadSessions() } }
            )

            Divider().frame(width: 1)

            // 主内容区
            mainContent
        }
        .background(HarnessTheme.bgPrimary)
        .frame(minWidth: 800, minHeight: 500)
        // P0.4 主题插件：激活主题即时生效（tint 全局传播 + Environment 注入观察）
        .tint(viewModel.activeThemeSpec.accentColor)
        .environment(\.harnessThemeSpec, viewModel.activeThemeSpec)
        // 折叠态：主区左上角展开按钮（Codex 式）
        .overlay(alignment: .topLeading) {
            if viewModel.isSidebarCollapsed {
                Button {
                    withAnimation(.smooth(duration: 0.18)) { viewModel.isSidebarCollapsed = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.secondary.opacity(0.08)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("展开侧边栏")
                .padding(10)
            }
        }
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
                onClear: { viewModel.clearToolResult(at: $0) },
                loadState: viewModel.toolsLoadState,
                loadWarning: viewModel.toolsLoadWarning,
                onRetry: { Task { await viewModel.retryLoadTools() } }
            )
        case .settings:
            SettingsView(viewModel: viewModel,
                         onSandboxChange: { viewModel.setSandboxRoot($0) },
                         onNotificationsChange: { viewModel.setNotificationsEnabled($0) },
                         accountService: viewModel.accountService)
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
