import Session
import SwiftUI

// MARK: - 会话列表项（单行 + hover 删除 + 相对时间 + 生成指示）

struct SessionListItem: View {
    let session: SessionRecord
    let title: String
    let isSelected: Bool
    let isGenerating: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    if isGenerating {
                        // Codex 式：在途任务运行中指示
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .frame(width: 12)
                    } else if session.metadata.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(HarnessTheme.accent)
                            .frame(width: 12)
                    } else {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? HarnessTheme.accent : HarnessTheme.textTertiary)
                    }
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                    Spacer(minLength: 4)
                    // Codex 式：行尾相对时间（生成中显示状态替代时间）
                    Text(isGenerating ? "生成中…" : RelativeTime.format(session.metadata.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(isGenerating ? HarnessTheme.accent : HarnessTheme.textTertiary)
                        .lineLimit(1)
                    if isHovered, !isSelected {
                        Button {
                            onTogglePin()
                        } label: {
                            Image(systemName: session.metadata.pinned ? "pin.slash" : "pin")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(HarnessTheme.textTertiary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .help(session.metadata.pinned ? "取消置顶" : "置顶（Codex 式 pinned）")
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(HarnessTheme.textTertiary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .help("删除对话")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? HarnessTheme.sidebarSelected.opacity(0.7)
                : isHovered ? HarnessTheme.sidebarHover
                : .clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isGenerating ? "\(title)，生成中" : "\(title)，\(RelativeTime.format(session.metadata.createdAt))")
    }
}

// MARK: - 相对时间（纯函数，可单测）

enum RelativeTime {
    /// 今天：刚刚 / N分钟前 / N小时前；昨天；<7天：N天前；否则 M月d日
    static func format(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let mins = max(0, Int(now.timeIntervalSince(date) / 60))
            if mins < 1 {
                return "刚刚"
            }
            if mins < 60 {
                return "\(mins)分钟前"
            }
            return "\(mins / 60)小时前"
        }
        if cal.isDateInYesterday(date) {
            return "昨天"
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 {
            return "\(days)天前"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}
