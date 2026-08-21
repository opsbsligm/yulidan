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
                Button("关闭") {}
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380, height: 420)
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
