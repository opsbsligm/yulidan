import SwiftUI

// 工具轨迹行（Codex 式：折叠摘要 + 展开入参/输出）
// 展示层模型 + UI 组件；对应 Agent 包 ToolTraceEntry

// MARK: - 展示层模型

/// 单条工具执行（展示层；对应 Agent.ToolTraceEntry）
struct ToolTraceItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let arguments: String
    let output: String
    let ok: Bool
}

// MARK: - 工具轨迹行（Codex 式：折叠摘要 + 展开入参/输出）

struct ToolTraceRow: View {
    let item: ToolTraceItem
    @State private var expanded = false

    private var argSummary: String {
        String(item.arguments.replacingOccurrences(of: "\n", with: " ").prefix(80))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HarnessTheme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                    Text(item.name)
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(HarnessTheme.textSecondary)
                    if !argSummary.isEmpty {
                        Text(argSummary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HarnessTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: item.ok ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(item.ok ? HarnessTheme.success : HarnessTheme.error)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !item.arguments.isEmpty {
                        TraceDetailBlock(title: "入参", text: item.arguments, maxHeight: 80)
                    }
                    if !item.output.isEmpty {
                        TraceDetailBlock(title: "输出", text: item.output, maxHeight: 160, isError: !item.ok)
                    }
                }
                .padding(.leading, 26)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(HarnessTheme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.leading, 34) // 对齐助手文本列（24 头像 + 10 间距）
        .frame(maxWidth: 520, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("工具 \(item.name) \(item.ok ? "执行成功" : "执行失败")")
        .accessibilityHint(expanded ? "轻点两次收起详情" : "轻点两次展开入参与输出")
    }
}

/// 轨迹详情块（入参/输出；等宽小字，限高内滚）
struct TraceDetailBlock: View {
    let title: String
    let text: String
    var maxHeight: CGFloat = 120
    var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HarnessTheme.textTertiary)
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isError ? HarnessTheme.warning : HarnessTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxHeight)
            .background(HarnessTheme.bgSecondary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}
