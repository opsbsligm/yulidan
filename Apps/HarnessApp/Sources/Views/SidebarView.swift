import Account
import Session
import SwiftUI
import Workspace

/// Codex 风格单栏侧边栏：
/// 品牌行（Harness ⌄ + 折叠 + 搜索 + 归档管理）→ 导航 → 搜索（可限定项目）
/// → 项目分区（新建/展开收起/右键重命名归档删除/拖拽迁移）→ 全局会话 → 底部头像
struct SidebarView: View {
    @Binding var selectedTab: AppTab
    @Binding var selectedSession: SessionRecord?
    let sessions: [SessionRecord]
    /// 全部项目（含归档；主区只展示未归档）
    let projects: [Project]
    /// 搜索中（展示扁平搜索结果，不分区）
    let isSearching: Bool
    /// 搜索限定项目（nil = 全局）
    let searchProjectScope: UUID?
    /// 正在生成的会话（Codex 式：列表行运行中指示）
    let generatingSessionId: SessionID?
    /// 折叠态（Codex 式：窄图标 rail）
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    /// 会话标题（由 ViewModel 提供，保证与重命名/自动标题一致）
    let titleFor: (SessionRecord) -> String
    let onNewSession: () -> Void
    let onSelectSession: (SessionRecord) -> Void
    let onTogglePin: (SessionRecord) -> Void
    let onDeleteSession: (SessionRecord) -> Void
    /// 搜索框输入变化回调（空串 = 清空）
    let onSearch: (String) -> Void
    /// 切换搜索限定项目（nil = 全局）
    let onSearchScope: (UUID?) -> Void
    // 项目操作（P0.2）
    let onCreateProject: (String) -> Void
    let onRenameProject: (Project, String) -> Void
    let onDeleteProject: (Project, DeleteProjectOption) -> Void
    let onToggleProjectArchived: (Project) -> Void
    let onToggleProjectCollapsed: (Project) -> Void
    let onMoveSession: (SessionRecord, ProjectDropTarget) -> Void
    let onToggleSessionArchived: (SessionRecord) -> Void
    let onUnarchiveProject: (Project) -> Void
    let onUnarchiveSession: (SessionRecord) -> Void
    /// 会话列表加载状态（P0.3 异常 UI；默认 .loaded 兼容 Preview 等静态调用方）
    var sessionsLoadState: NavLoadState = .loaded
    /// 会话列表加载失败重试
    var onRetryLoadSessions: () -> Void = {}
    /// P2.2.2：账号服务（底栏 / rail 底部 iCloud 同步状态提示；nil = 未挂接，隐藏）
    var accountService: AccountService?
    /// 点按同步提示 → 设置「账号与同步」子页深链
    var onOpenAccount: () -> Void = {}

    @State private var searchText = ""
    @State private var showSearch = false
    /// 新建项目弹窗
    @State private var showNewProject = false
    @State private var newProjectName = ""
    /// 归档管理面板
    @State private var showArchiveManager = false
    /// P1.3：展开/折叠两面共享 namespace（同 ID 同 namespace → 折叠/展开时原生 morph，铁律 4）
    @Namespace private var sidebarMorphNS
    /// P1.3：侧边栏折叠 morph 身份（展开/折叠玻璃面统一 ID）
    private static let collapseMorphID = "harness-sidebar-collapse"

    /// 用户姓名首字（头像用）
    private var avatarInitial: String {
        String(NSFullUserName().prefix(1))
    }

    /// 侧栏分区模型（纯函数；主区排除归档项）
    private var model: SidebarModel {
        SidebarModelBuilder.build(projects: projects, sessions: sessions)
    }

    /// 活跃（未归档）项目
    private var activeProjects: [Project] {
        projects.filter { !$0.archived }
    }

    /// 归档管理数据
    private var archiveModel: SidebarModel {
        SidebarModelBuilder.build(projects: projects, sessions: sessions)
    }

    /// 新对话：切回对话页并创建会话
    private func startNewChat() {
        if selectedTab != .chat {
            withAnimation(.smooth(duration: 0.18)) { selectedTab = .chat }
        }
        onNewSession()
    }

    var body: some View {
        Group {
            if isCollapsed {
                collapsedBody
            } else {
                expandedBody
            }
        }
        // P1.3：展开/折叠双态共享同一容器（morph 面同一 GlassEffectContainer；跨态组合未官方实证，
        // 铁律 1 注记：最坏 = 交叉淡变不 morph，功能不受损，实机走查判定）
        .glassSurfaceContainer()
        // 新建项目
        .alert("新建项目", isPresented: $showNewProject) {
            TextField("项目名称", text: $newProjectName)
            Button("创建") {
                onCreateProject(newProjectName)
                newProjectName = ""
            }
            Button("取消", role: .cancel) { newProjectName = "" }
        }
        // 归档管理
        .sheet(isPresented: $showArchiveManager) {
            ArchiveManagerView(
                archivedProjects: archiveModel.archivedProjects,
                archivedSessions: archiveModel.archivedSessions,
                titleFor: titleFor,
                onUnarchiveProject: { onUnarchiveProject($0) },
                onUnarchiveSession: { onUnarchiveSession($0) }
            )
        }
    }

    // MARK: - 展开态（宽 260）

    private var expandedBody: some View {
        VStack(spacing: 0) {
            // 顶部品牌行（Codex 式：名称 ⌄ + 折叠 + 搜索 + 归档管理）
            HStack(spacing: 2) {
                Menu {
                    Button {
                        onNewSession()
                    } label: {
                        Label("新建对话", systemImage: "plus")
                    }
                    Button {
                        selectedTab = .settings
                    } label: {
                        Label("设置", systemImage: "gear")
                    }
                    Divider()
                    Button("归档管理") {
                        showArchiveManager = true
                    }
                    Button("关于 Harness") {
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Harness").font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(HarnessTheme.textPrimary)
                    .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("Harness 菜单")

                Spacer()

                // 折叠（Codex 式：收起为窄 rail）
                Button(action: onToggleCollapse) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.secondary.opacity(0.08)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("折叠侧边栏")

                Button {
                    withAnimation(.smooth(duration: 0.15)) { showSearch.toggle() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.secondary.opacity(0.08)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("搜索对话")

                Button {
                    showArchiveManager = true
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.secondary.opacity(0.08)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("归档管理（项目/会话）")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // 搜索（点击图标展开；可限定项目范围）
            if showSearch {
                HStack(spacing: 6) {
                    Menu(content: {
                        Button("全部对话", action: { onSearchScope(nil) })
                        if !activeProjects.isEmpty {
                            Divider()
                            ForEach(activeProjects) { project in
                                Button(project.name) {
                                    onSearchScope(project.id.rawValue)
                                }
                            }
                        }
                    }, label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(searchProjectScope == nil
                                ? HarnessTheme.textTertiary : HarnessTheme.accent)
                    })
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("搜索范围")

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                    TextField("搜索对话", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { onSearch(searchText) }
                        .onChange(of: searchText) { _, newValue in
                            onSearch(newValue)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(HarnessTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            // P1.2：Tab 分段 Morph 流动玻璃（目标 P1 §2 核心件）
            // 新对话（瞬时动作，⌘N）+ 五面板（⌘1–⌘5，与折叠 rail 一致）
            // 选中玻璃面同 namespace 同 ID → 切换时原生 morph（❌ 禁 ZStack 滑块模拟，铁律 4）
            GlassMorphTabBar(
                segments: MorphTabSegment.sidebarDefault,
                selectedID: MorphTabSegment.selectedID(for: selectedTab),
                onSelect: { seg in
                    switch seg.action {
                    case .newChat:
                        startNewChat()
                    case let .select(tab):
                        if tab != selectedTab {
                            selectedTab = tab
                        }
                    }
                }
            )
            .padding(.bottom, 4)

            // 会话列表（常显；搜索模式 = 扁平结果；否则 = 项目分区 + 全局）
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if isSearching {
                        ForEach(sessions) { session in
                            SidebarSessionRow(
                                session: session,
                                inProject: SidebarModelBuilder.project(
                                    for: session, in: projects
                                )?.id,
                                title: titleFor(session),
                                isSelected: selectedSession?.id == session.id,
                                isGenerating: generatingSessionId == session.id,
                                onSelect: { onSelectSession(session) },
                                onTogglePin: { onTogglePin(session) },
                                onDelete: { onDeleteSession($0) },
                                onToggleArchive: { onToggleSessionArchived(session) }
                            )
                        }
                        if sessions.isEmpty {
                            Text("无匹配对话")
                                .font(.system(size: 12))
                                .foregroundStyle(HarnessTheme.textTertiary)
                                .padding(.vertical, 12)
                        }
                    } else {
                        // 加载异常态（P0.3：失败=错误行+重试；加载中空列表=占位行防空态闪烁）
                        if case let .failed(msg) = sessionsLoadState {
                            sessionsLoadFailureRow(msg)
                        } else if sessionsLoadState.isLoading, sessions.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("会话加载中…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(HarnessTheme.textTertiary)
                            }
                            .padding(.vertical, 12)
                            .padding(.leading, 8)
                        }
                        SidebarProjectSections(
                            model: model,
                            sessions: sessions,
                            selectedSession: selectedSession,
                            generatingSessionId: generatingSessionId,
                            titleFor: titleFor,
                            onSelectSession: onSelectSession,
                            onTogglePin: onTogglePin,
                            onDeleteSession: onDeleteSession,
                            onNewProject: {
                                newProjectName = ""
                                showNewProject = true
                            },
                            onToggleProjectCollapsed: onToggleProjectCollapsed,
                            onRenameProject: onRenameProject,
                            onArchiveProject: onToggleProjectArchived,
                            onDeleteProject: onDeleteProject,
                            onMoveSession: onMoveSession,
                            onToggleSessionArchived: onToggleSessionArchived
                        )
                    }
                }
                .padding(.horizontal, 6)
            }

            // 底栏（Codex 式：设置 + 头像；与折叠态 rail 对齐）
            // P0 实机验收发现（2026-08-26）：展开态此前无底栏，设置仅能从顶部「Harness ⌄」菜单进入，
            // 进入后侧边栏无「当前在设置」指示、无持久返回入口，用户点进设置后无路可退
            SidebarBottomBar(
                selectedTab: $selectedTab,
                onToggleCollapse: onToggleCollapse,
                accountService: accountService,
                onOpenAccount: onOpenAccount
            )
        }
        .frame(width: 260)
        // P1.3：与折叠面同 ID 同 namespace 同 .regular 变体同型 shape（cornerRadius 0）→ 折叠/展开原生 morph
        .glassSurface(
            .regular,
            cornerRadius: 0,
            morphID: Self.collapseMorphID,
            namespace: sidebarMorphNS,
            transition: .matchedGeometry
        )
    }

    /// 会话列表加载失败行（P0.3 异常 UI；已加载部分仍渲染在下方）
    private func sessionsLoadFailureRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(HarnessTheme.error)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(HarnessTheme.error)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button("重试", action: onRetryLoadSessions)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
    }

    // MARK: - 折叠态（窄 rail，保持原有交互）

    private var collapsedBody: some View {
        VStack(spacing: 2) {
            Button(action: startNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundStyle(HarnessTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.secondary.opacity(0.08)))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("新对话（⌘N）")
            .keyboardShortcut("n", modifiers: .command)

            ForEach([AppTab.chat, .agents, .plugins, .skills, .tools], id: \.self) { tab in
                Button {
                    withAnimation(.smooth(duration: 0.18)) { selectedTab = tab }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? HarnessTheme.accent : HarnessTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            selectedTab == tab
                                ? Circle().fill(HarnessTheme.sidebarHover)
                                : Circle().fill(.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .modifier(NavShortcutModifier(index: NavRowShortcut.index(for: tab)))
            }

            Spacer()

            Button {
                showArchiveManager = true
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 14))
                    .foregroundStyle(HarnessTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.secondary.opacity(0.08)))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("归档管理（项目/会话）")

            // P2.2.2：iCloud 同步状态图标（本地模式 = hidden 自动隐藏）
            if let accountService {
                SidebarSyncHintIcon(accountService: accountService, onOpenAccount: onOpenAccount)
            }
            Button {
                withAnimation(.smooth(duration: 0.18)) { selectedTab = .settings }
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14))
                    .foregroundStyle(selectedTab == .settings ? HarnessTheme.accent : HarnessTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        selectedTab == .settings
                            ? Circle().fill(HarnessTheme.sidebarHover)
                            : Circle().fill(.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("设置（⌘,）")
            .keyboardShortcut(",", modifiers: .command)

            // 头像（点击展开侧边栏）
            Button(action: onToggleCollapse) {
                ZStack {
                    Circle().fill(HarnessTheme.surface)
                    Text(avatarInitial)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HarnessTheme.accent)
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("展开侧边栏")
            .padding(.bottom, 10)
        }
        .frame(width: 52)
        // P1.3：与展开面同 ID 同 namespace（level 仅影响 legacy/solid fallback 材质，原生 Glass 值恒为
        // resolvedGlass .regular+tint → 两态同变体，满足官方 morph 约束）
        .glassSurface(
            .prominent,
            cornerRadius: 0,
            morphID: Self.collapseMorphID,
            namespace: sidebarMorphNS,
            transition: .matchedGeometry
        )
    }
}

#Preview {
    ZStack {
        HarnessTheme.bgPrimary
        SidebarView(
            selectedTab: .constant(.chat),
            selectedSession: .constant(nil),
            sessions: [],
            projects: [],
            isSearching: false,
            searchProjectScope: nil,
            generatingSessionId: nil,
            isCollapsed: false,
            onToggleCollapse: {},
            titleFor: { _ in "示例对话" },
            onNewSession: {},
            onSelectSession: { _ in },
            onTogglePin: { _ in },
            onDeleteSession: { _ in },
            onSearch: { _ in },
            onSearchScope: { _ in },
            onCreateProject: { _ in },
            onRenameProject: { _, _ in },
            onDeleteProject: { _, _ in },
            onToggleProjectArchived: { _ in },
            onToggleProjectCollapsed: { _ in },
            onMoveSession: { _, _ in },
            onToggleSessionArchived: { _ in },
            onUnarchiveProject: { _ in },
            onUnarchiveSession: { _ in }
        )
    }
    .frame(width: 260, height: 500)
}
