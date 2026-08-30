import SwiftUI

// P2.1 设置弹窗完整页面（Apple 账号状态 / iCloud 同步 / 模型 / MCP / RAG / 权限 / 主题）
// 设计：单页滚动（七卡片概览）作为大弹窗（Sheet）展示；详细编辑跳转回侧边栏设置页。

struct SettingsCompletePage: View {
    var viewModel: AppViewModel
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
                    accountCard
                    iCloudCard
                    modelCard
                    mcpCard
                    ragCard
                    permissionCard
                    themeCard
                }
                .padding(20)
            }
        }
        .frame(width: 700, height: 600)
    }

    /// 卡片外壳（标题 + 说明 + 内容，统一视觉）
    private func card(title: String, detail: String, content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.headline, design: .rounded)).fontWeight(.semibold)
                .foregroundStyle(HarnessTheme.textPrimary)
            Text(detail).font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HarnessTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 卡片一：Apple 账号状态（登录状态 + 账号名 + 模式 + 登录/登出按钮）

    private var accountCard: some View {
        card(title: "Apple 账号状态", detail: "登录状态、账号名称、登录模式（离线 / Apple SSO + iCloud）", content: {
            HStack(spacing: 12) {
                // 账号名（displayName 或 email，nil = 未登录）+ 模式 + 登录/登出按钮
                Text(viewModel.accountService.account.map { $0.displayName ?? $0.email ?? "未登录" } ?? "未登录")
                    .font(.system(size: 13)).foregroundStyle(HarnessTheme.textPrimary)
                Text(viewModel.accountService.state.isICloudReady ? "Apple SSO + iCloud 同步模式" : "离线本地模式")
                    .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                if viewModel.accountService.account != nil {
                    Button("登出") { viewModel.accountService.signOut() }.controlSize(.small)
                } else {
                    Button("登录") { viewModel.accountService.signInWithApple() }.controlSize(.small)
                }
            }
        })
    }

    // MARK: - 卡片二：iCloud 同步指示器（工作区根目录 + 权限状态）

    private var iCloudCard: some View {
        card(title: "iCloud 同步指示器", detail: "工作区根目录（本地磁盘 / iCloud 容器）与同步权限", content: {
            // 工作区标签（本地磁盘 / iCloud 容器）+ 根路径（可读；verbatim 走 String 插值，避免 LocalizedStringKey 弃用告警，渲染逐字一致）
            Text(verbatim: "工作区：\(viewModel.workspaceRouter.current.kind)（\(viewModel.workspaceRouter.current.rootURL.path)）")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
        })
    }

    // MARK: - 卡片三：模型配置（提供商、模型、上下文、思考）

    private var modelCard: some View {
        card(title: "模型配置", detail: "提供商、模型、上下文窗口、思考等级（摘要）", content: {
            // 摘要行（详细编辑跳转设置页模型服务子页）
            Text("提供商：\(viewModel.llmConfig.provider.displayName) · 模型：\(viewModel.llmConfig.modelName)")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
        })
    }

    // MARK: - 卡片四：MCP 服务配置（插件计数 + 启用/禁用切换）

    private var mcpCard: some View {
        card(title: "MCP 服务配置", detail: "已安装插件数量与启用/禁用开关（摘要）", content: {
            // 插件计数（完整管理跳转插件页）
            Text("已安装插件：\(viewModel.mcpServers.count) 个")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
        })
    }

    // MARK: - 卡片五：RAG 记忆参数（分块、向量库路径）

    private var ragCard: some View {
        card(title: "RAG 记忆参数", detail: "向量库路径、分块大小（摘要）", content: {
            Text("向量库路径：\(viewModel.workspaceRouter.ragIndexURL.path)")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
        })
    }

    // MARK: - 卡片六：权限总览（iCloud、通知、沙箱权限）

    private var permissionCard: some View {
        card(title: "权限总览", detail: "iCloud、通知、文件沙箱权限状态", content: {
            // 权限行（授权/拒绝 + 重新申请引导）
            Text("iCloud：\(viewModel.accountService.state.isICloudReady ? "已授权" : "未授权或拒绝")")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
        })
    }

    // MARK: - 卡片七：主题切换入口（主题插件选择器）

    private var themeCard: some View {
        card(title: "主题切换入口", detail: "主题插件（本地插件 / MCP 主题服务器）切换", content: {
            // 主题选择器（下拉）+ 玻璃参数明示（P1.4 单点）
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
