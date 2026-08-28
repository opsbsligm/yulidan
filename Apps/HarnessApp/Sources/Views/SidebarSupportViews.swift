import Session
import SwiftUI
import Workspace

// MARK: - 归档管理面板（P0.2：查看/取消归档；取消归档回落原项目或全局）

struct ArchiveManagerView: View {
    let archivedProjects: [Project]
    let archivedSessions: [SessionRecord]
    let titleFor: (SessionRecord) -> String
    let onUnarchiveProject: (Project) -> Void
    let onUnarchiveSession: (SessionRecord) -> Void
    /// sheet 自关闭（P0 实机验收发现：原「关闭」按钮为空闭包假按钮，macOS sheet 无滑动手势，用户无法关闭，2026-08-26）
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("归档管理").font(.system(size: 15, weight: .semibold))
            Divider()
            if archivedProjects.isEmpty, archivedSessions.isEmpty {
                Text("暂无归档内容")
                    .font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !archivedProjects.isEmpty {
                            Text("归档项目（\(archivedProjects.count)）")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HarnessTheme.textTertiary)
                            ForEach(archivedProjects) { project in
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundStyle(HarnessTheme.textSecondary)
                                    Text(project.name)
                                        .font(.system(size: 13))
                                    Spacer()
                                    Button("恢复") { onUnarchiveProject(project) }
                                        .controlSize(.small)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        if !archivedSessions.isEmpty {
                            Text("归档会话（\(archivedSessions.count)）")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HarnessTheme.textTertiary)
                                .padding(.top, 4)
                            ForEach(archivedSessions) { session in
                                HStack {
                                    Image(systemName: "bubble.right")
                                        .foregroundStyle(HarnessTheme.textSecondary)
                                    Text(titleFor(session))
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Spacer()
                                    Button("恢复") { onUnarchiveSession(session) }
                                        .controlSize(.small)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380, height: 420)
    }
}

// MARK: - 导航行（图标 + 文字）

/// ⌘1–⌘5 面板快捷键索引（展开/折叠两态共用；settings 走 macOS 标准 ⌘,，由底栏齿轮承载）
enum NavRowShortcut {
    static func index(for tab: AppTab) -> Int? {
        switch tab {
        case .chat: 1
        case .agents: 2
        case .plugins: 3
        case .skills: 4
        case .tools: 5
        case .settings: nil // ⌘, 由底栏齿轮承载；不注册 ⌘6（与折叠态 rail 一致）
        }
    }
}

// MARK: - 侧边栏底栏（展开态；Codex 式：设置 + 头像，与折叠态 rail 对齐）

/// 展开态侧边栏底栏：设置行（⌘,，选中态高亮）+ 头像行（点击折叠侧边栏）。
/// P0 实机验收发现（2026-08-26）：展开态此前无底栏，设置仅能从顶部「Harness ⌄」菜单进入，
/// 进入后无「当前在设置」指示、无持久返回入口，用户点进设置后无路可退
struct SidebarBottomBar: View {
    @Binding var selectedTab: AppTab
    let onToggleCollapse: () -> Void
    /// 设置行 hover
    @State private var settingsHover = false

    /// 用户姓名首字（头像用）
    private var avatarInitial: String {
        String(NSFullUserName().prefix(1))
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 10)
            VStack(spacing: 2) {
                Button {
                    withAnimation(.smooth(duration: 0.18)) { selectedTab = .settings }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: AppTab.settings.icon)
                            .font(.system(size: 14, weight: selectedTab == .settings ? .semibold : .regular))
                            .frame(width: 18)
                            .foregroundStyle(
                                selectedTab == .settings ? HarnessTheme.accent
                                    : settingsHover ? HarnessTheme.textPrimary
                                    : HarnessTheme.textSecondary
                            )
                        Text("设置")
                            .font(.system(size: 13, weight: selectedTab == .settings ? .medium : .regular))
                            .foregroundStyle(
                                selectedTab == .settings || settingsHover
                                    ? HarnessTheme.textPrimary
                                    : HarnessTheme.textSecondary
                            )
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == .settings ? Color.blue.opacity(0.12) :
                        settingsHover ? HarnessTheme.surface : .clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { settingsHover = $0 }
                .keyboardShortcut(",", modifiers: .command)
                .help("设置（⌘,）")
                .padding(.horizontal, 6)
                .accessibilityAddTraits(selectedTab == .settings ? .isSelected : [])

                Button(action: onToggleCollapse) {
                    HStack(spacing: 9) {
                        ZStack {
                            Circle().fill(HarnessTheme.surface)
                            Text(avatarInitial)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HarnessTheme.accent)
                        }
                        .frame(width: 20, height: 20)
                        Text(NSFullUserName())
                            .font(.system(size: 12))
                            .foregroundStyle(HarnessTheme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 10))
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("折叠侧边栏")
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
        }
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
