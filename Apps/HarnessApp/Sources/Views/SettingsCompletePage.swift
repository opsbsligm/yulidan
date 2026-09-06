import SwiftUI

// P2.1 设置弹窗完整页面（本地工作区 / 模型 / MCP / RAG / 主题）
// 设计：单页滚动（五卡片概览）作为大弹窗（Sheet）展示；详细编辑跳转回侧边栏设置页。
// 2026-08-30：SSO/iCloud 模块整体移除 → 原「Apple 账号状态 / iCloud 同步指示器 / 权限总览」三卡删除。
// 2026-09-06（D-8/D-9/D-12 本批）：
//   · D-8 概览页**保留**，每行加「编辑…」跳转到对应编辑 pane（映射 = SettingsOverviewCard，纯函数可单测）；
//   · D-9 无编辑入口的信息（工作区根目录 / 向量库路径）明示**只读**并给出原因文案，
//         不再让用户误判「这里能改」（IA-4 二选一里选的这一支：冻结前夜不扩能力面）；
//   · D-12/F5 撤掉卡片的不透明自铺底（A18），系统 sheet 材质得以透出。

/// 概览卡 → 编辑 pane 的映射（D-8 的单一权威映射；纯数据，可单测）
///
/// ⚠️ `editPane == nil` 的含义是**全仓没有该信息的编辑入口**（实测：工作区根固定在
/// Application Support/Harness，由 `WorkspaceRootProvider` 决定，界面无入口；RAG 向量库路径
/// 随工作区根派生、分块参数无界面入口）⇒ 该卡改为「只读」明示（D-9），**不得**为了凑
/// 「每行都有按钮」而把跳转指到语义不符的 pane（那是把用户引到更远的误解里）。
enum SettingsOverviewCard: String, CaseIterable, Identifiable, Hashable {
    case workspace
    case model
    case mcp
    case rag
    case theme

    var id: String {
        rawValue
    }

    /// 「编辑…」跳转目标；nil = 无编辑入口（该卡按只读呈现）
    var editPane: SettingsSubTab? {
        switch self {
        case .workspace: nil
        case .model: .providers
        case .mcp: .pluginManagement
        case .rag: nil
        case .theme: .preferences
        }
    }

    /// 只读卡的原因说明（仅 editPane == nil 时使用）
    var readOnlyNote: String? {
        switch self {
        case .workspace:
            "只读 · 工作区根目录由启动时的应用支持目录决定，当前版本不提供修改入口"
        case .rag:
            "只读 · 向量库路径随工作区根目录派生；分块参数当前无界面入口"
        case .model, .mcp, .theme:
            nil
        }
    }
}

struct SettingsCompletePage: View {
    var viewModel: AppViewModel
    /// 概览页「编辑…」跳转回调（D-8）：由 SettingsView 负责关弹窗 + 跨分类切 pane
    var onEdit: ((SettingsSubTab) -> Void) = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // 大弹窗（Sheet）：单页滚动 = 完整页面（非侧边栏导航，区别于 SettingsView）
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题行 + 关闭（2026-08-30 锁屏静态审计发现：原 sheet 无任何关闭途径，
            // 用户点进「完整设置」后无法返回——与 08-26 归档管理假按钮同类缺陷；
            // 按 ArchiveManagerView/MCPServerLogSheet 既有模式补 dismiss + ⌘. 双通道）
            HStack(spacing: 8) {
                Text("完整设置").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HarnessTheme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.08)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("关闭完整设置，返回设置页")
                .accessibilityLabel("关闭完整设置")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    workspaceCard
                    modelCard
                    mcpCard
                    ragCard
                    themeCard
                }
                .padding(20)
            }
        }
        .frame(width: 700, height: 600)
    }

    /// 卡片外壳（标题 + 说明 + 内容，统一视觉）
    ///
    /// D-12/F5（A18 修法）：卡底由不透明 `HarnessTheme.surface` 改为半透明
    /// （`surface.opacity(0.5)`，与 `MCPServerViews` 在 sheet 内既有子项背景同口径）——
    /// 透明窗底（D-10(a)）之下不透明自铺底会挡住系统 sheet 材质的透出。
    /// ⚠️ 属可见状态变化：观感终裁归 G3 池 A 目检（本仓 A 层无玻璃像素通道，不自证）。
    private func card(
        _ overview: SettingsOverviewCard,
        title: String,
        detail: String,
        content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.headline, design: .rounded)).fontWeight(.semibold)
                        .foregroundStyle(HarnessTheme.textPrimary)
                    Text(detail).font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                }
                Spacer(minLength: 8)
                headerAction(for: overview)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HarnessTheme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 卡头右侧动作：有编辑 pane → 「编辑…」跳转（D-8）；无编辑入口 → 只读标记（D-9）
    @ViewBuilder
    private func headerAction(for overview: SettingsOverviewCard) -> some View {
        if let pane = overview.editPane {
            Button("编辑…") {
                onEdit(pane)
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .accessibilityLabel("编辑\(pane.title)")
        } else if let note = overview.readOnlyNote {
            Text("只读")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HarnessTheme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.08)))
                .help(note)
                .accessibilityLabel(note)
        }
    }

    // MARK: - 卡片一：本地工作区（根目录，只读）

    private var workspaceCard: some View {
        card(.workspace, title: "本地工作区", detail: "Agent 产出 / RAG 向量库 / 插件元数据 / 主题资源 / 长期记忆 的本地根目录", content: {
            // 根路径（只读；verbatim 走 String 插值，避免 LocalizedStringKey 弃用告警）
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "工作区：\(viewModel.workspaceRouter.current.rootURL.path)")
                    .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
                if let note = SettingsOverviewCard.workspace.readOnlyNote {
                    Text(verbatim: note)
                        .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                }
            }
        })
    }

    // MARK: - 卡片二：模型配置（提供商、模型、上下文、思考）

    private var modelCard: some View {
        card(.model, title: "模型配置", detail: "提供商、模型、上下文窗口、思考等级（摘要）", content: {
            // 摘要行（编辑入口＝卡头「编辑…」→ 模型服务/提供商与密钥，D-8）
            Text("提供商：\(viewModel.llmConfig.provider.displayName) · 模型：\(viewModel.llmConfig.modelName)")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
        })
    }

    // MARK: - 卡片三：MCP 服务配置（插件计数）

    private var mcpCard: some View {
        card(.mcp, title: "MCP 服务配置", detail: "已安装插件数量（摘要）", content: {
            // 插件计数（编辑入口＝卡头「编辑…」→ 插件/插件管理，D-8）
            Text("已安装插件：\(viewModel.mcpServers.count) 个")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
        })
    }

    // MARK: - 卡片四：RAG 记忆参数（向量库路径，只读）

    private var ragCard: some View {
        card(.rag, title: "RAG 记忆参数", detail: "向量库路径（随工作区根目录派生）", content: {
            VStack(alignment: .leading, spacing: 4) {
                Text("向量库路径：\(viewModel.workspaceRouter.ragIndexURL.path)")
                    .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
                if let note = SettingsOverviewCard.rag.readOnlyNote {
                    Text(verbatim: note)
                        .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                }
            }
        })
    }

    // MARK: - 卡片五：主题切换入口（主题插件选择器）

    private var themeCard: some View {
        card(.theme, title: "主题切换入口", detail: "主题插件（本地插件 / MCP 主题服务器）切换", content: {
            // 主题选择器（下拉）+ 玻璃参数明示（P1.4 单点）；卡头「编辑…」= 通用/偏好（玻璃参数说明所在）
            Picker("主题插件", selection: Binding(
                get: { viewModel.activeThemeSpec.id },
                set: { viewModel.applyTheme(id: $0) }
            )) {
                ForEach(viewModel.themeOptions) { option in
                    Text(option.isSystem ? option.spec.name : "\(option.spec.name) · \(option.sourceName)").tag(option.id)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 300)
        })
    }
}
