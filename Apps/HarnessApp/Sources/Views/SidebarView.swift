import Session
import SwiftUI

/// Codex 风格单栏侧边栏：
/// 品牌行（Harness ⌄ + 搜索图标）→ 导航（新对话⊕ / 对话 / 插件 / 工具）→ 会话列表（常显）→ 底部头像+姓名
struct SidebarView: View {
    @Binding var selectedTab: AppTab
    @Binding var selectedSession: SessionRecord?
    let sessions: [SessionRecord]
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

    @State private var searchText = ""
    @State private var showSearch = false
    @State private var newHover = false

    /// 用户姓名首字（头像用）
    private var avatarInitial: String {
        String(NSFullUserName().prefix(1))
    }

    /// 新对话：切回对话页并创建会话
    private func startNewChat() {
        if selectedTab != .chat {
            withAnimation(.smooth(duration: 0.18)) { selectedTab = .chat }
        }
        onNewSession()
    }

    private var filtered: [SessionRecord] {
        searchText.isEmpty
            ? sessions
            : sessions.filter { titleFor($0).localizedCaseInsensitiveContains(searchText) }
    }

    /// 分组（纯函数见 SessionGroups）：置顶（最顶）→ 今天 / 昨天 / 更早
    private var groups: [(label: String, items: [SessionRecord])] {
        SessionGroups.group(filtered)
    }

    var body: some View {
        if isCollapsed {
            collapsedBody
        } else {
            expandedBody
        }
    }

    // MARK: - 展开态（宽 260）

    private var expandedBody: some View {
        VStack(spacing: 0) {
            // 顶部品牌行（Codex 式：名称 ⌄ + 折叠 + 搜索图标）
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
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // 搜索（点击图标展开）
            if showSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                    TextField("搜索对话", text: $searchText)
                        .onChange(of: searchText) { _, newValue in
                            onSearch(newValue)
                        }
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(HarnessTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(HarnessTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // 导航区
            VStack(spacing: 1) {
                // 新对话（Codex 式：行尾 ⊕）
                Button(action: startNewChat) {
                    HStack(spacing: 9) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                            .frame(width: 18)
                            .foregroundStyle(newHover ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                        Text("新对话")
                            .font(.system(size: 13))
                            .foregroundStyle(newHover ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(newHover ? HarnessTheme.sidebarHover.opacity(0.6) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { newHover = $0 }
                .keyboardShortcut("n", modifiers: .command)
                .padding(.bottom, 4)

                ForEach([AppTab.chat, .agents, .plugins, .skills, .tools], id: \.self) { tab in
                    NavRow(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.smooth(duration: 0.18)) { selectedTab = tab }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 10)

            Divider().frame(height: 1).padding(.horizontal, 12)

            // 会话列表（Codex 式：任务列表常显，按日分组）
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if groups.isEmpty {
                        Text(searchText.isEmpty ? "暂无对话，点击「新对话」开始" : "无匹配结果")
                            .font(.system(size: 12))
                            .foregroundStyle(HarnessTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                    ForEach(groups, id: \.label) { group in
                        Text(group.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HarnessTheme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 3)
                        ForEach(group.items) { session in
                            SessionListItem(
                                session: session,
                                title: titleFor(session),
                                isSelected: selectedSession?.id == session.id,
                                isGenerating: session.id == generatingSessionId,
                                onSelect: { onSelectSession(session) },
                                onTogglePin: { onTogglePin(session) },
                                onDelete: { onDeleteSession(session) }
                            )
                            .padding(.horizontal, 4)
                        }
                    }
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 8)
            }

            // 底栏：头像+姓名（可点菜单） | 设置齿轮
            Divider().frame(height: 1).padding(.horizontal, 12)
            HStack(spacing: 4) {
                Menu {
                    Button {
                        selectedTab = .settings
                    } label: {
                        Label("设置", systemImage: "gear")
                    }
                    Button {
                        onNewSession()
                    } label: {
                        Label("新建对话", systemImage: "plus")
                    }
                    Divider()
                    Button("关于 Harness") {
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(HarnessTheme.surface)
                            Text(avatarInitial)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HarnessTheme.accent)
                        }
                        .frame(width: 26, height: 26)
                        Text(NSFullUserName())
                            .font(.system(size: 13))
                            .foregroundStyle(HarnessTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("账户菜单")

                Spacer()

                Button {
                    selectedTab = .settings
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            selectedTab == .settings
                                ? HarnessTheme.sidebarHover
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("设置（⌘,）")
                .keyboardShortcut(",", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 260)
        .glassSurface(.prominent, cornerRadius: 0)
    }

    // MARK: - 折叠态（窄图标 rail，宽 52）

    private var collapsedBody: some View {
        VStack(spacing: 2) {
            Button(action: onToggleCollapse) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundStyle(HarnessTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.secondary.opacity(0.08)))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("展开侧边栏")
            .padding(.top, 14)
            .padding(.bottom, 8)

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
        .glassSurface(.prominent, cornerRadius: 0)
    }
}

// MARK: - 导航行（图标 + 文字）

/// ⌘1–⌘6 面板快捷键索引（展开/折叠两态共用）
enum NavRowShortcut {
    static func index(for tab: AppTab) -> Int? {
        switch tab {
        case .chat: 1
        case .agents: 2
        case .plugins: 3
        case .skills: 4
        case .tools: 5
        case .settings: 6
        }
    }
}

struct NavRow: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    /// ⌘1–⌘6 面板快捷键（Codex 式；settings 走 ⌘6 由底栏齿轮承载）
    private var shortcutIndex: Int? {
        NavRowShortcut.index(for: tab)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundStyle(
                        isSelected ? HarnessTheme.accent
                            : isHovered ? HarnessTheme.textPrimary
                            : HarnessTheme.textSecondary
                    )
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(
                        isSelected ? HarnessTheme.textPrimary
                            : isHovered ? HarnessTheme.textPrimary
                            : HarnessTheme.textSecondary
                    )
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? HarnessTheme.sidebarHover
                    : isHovered ? HarnessTheme.sidebarHover.opacity(0.6)
                    : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .modifier(NavShortcutModifier(index: shortcutIndex))
    }
}

/// 条件键盘快捷键（index 为 nil 时不附加，避免与 ⌘6 齿轮重复绑定）
struct NavShortcutModifier: ViewModifier {
    let index: Int?
    func body(content: Content) -> some View {
        if let index {
            content.keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
        } else {
            content
        }
    }
}

// MARK: - 会话分组（纯函数，可单测）

enum SessionGroups {
    /// 置顶（Codex 式 pinned 段，最顶）→ 今天 / 昨天 / 更早（组内按创建时间倒序）
    static func group(_ filtered: [SessionRecord], now: Date = Date()) -> [(label: String, items: [SessionRecord])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        var out: [(label: String, items: [SessionRecord])] = []
        let sorted = filtered.sorted { $0.metadata.createdAt > $1.metadata.createdAt }
        let pinnedItems = sorted.filter(\.metadata.pinned)
        if !pinnedItems.isEmpty {
            out.append(("置顶", pinnedItems))
        }
        let rest = sorted.filter { !$0.metadata.pinned }
        let todayItems = rest.filter { $0.metadata.createdAt >= today }
        let yesterdayItems = rest.filter { $0.metadata.createdAt >= yesterday && $0.metadata.createdAt < today }
        let earlierItems = rest.filter { $0.metadata.createdAt < yesterday }
        if !todayItems.isEmpty {
            out.append(("今天", todayItems))
        }
        if !yesterdayItems.isEmpty {
            out.append(("昨天", yesterdayItems))
        }
        if !earlierItems.isEmpty {
            out.append(("更早", earlierItems))
        }
        return out
    }
}

#Preview {
    ZStack {
        HarnessTheme.bgPrimary
        SidebarView(
            selectedTab: .constant(.chat),
            selectedSession: .constant(nil),
            sessions: [],
            generatingSessionId: nil,
            isCollapsed: false,
            onToggleCollapse: {},
            titleFor: { _ in "示例对话" },
            onNewSession: {},
            onSelectSession: { _ in },
            onTogglePin: { _ in },
            onDeleteSession: { _ in },
            onSearch: { _ in }
        )
    }
    .frame(width: 260, height: 500)
}
