import SwiftUI

// MARK: - 模型切换器（P0.5.2：顶栏 pill 与 composer 底行右下角共用同一真实链路）

//
// 提供商 → 模型两级选择；切换即存（llmConfig.save）并 toast 回显。
// 顶栏 pill 与 composer「右下角模型下拉」复用本组件，避免两套切换逻辑漂移。

struct ModelSwitcherMenu: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var hovered = false

    var body: some View {
        Menu {
            ForEach(ModelProvider.allCases, id: \.self) { provider in
                let models = provider.selectableModels.isEmpty
                    ? [viewModel.llmConfig.modelName]
                    : provider.selectableModels
                Section(provider.displayName) {
                    ForEach(models, id: \.self) { model in
                        Button {
                            select(provider: provider, model: model)
                        } label: {
                            if viewModel.llmConfig.provider == provider, viewModel.llmConfig.modelName == model {
                                Label(model, systemImage: "checkmark")
                            } else {
                                Text(model)
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                viewModel.selectedTab = .settings
            } label: {
                Label("模型设置…", systemImage: "gear")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: viewModel.llmConfig.provider.icon)
                    .font(.system(size: 11))
                Text(viewModel.llmConfig.modelName)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .foregroundStyle(hovered ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(hovered ? Color.secondary.opacity(0.1) : .clear))
            .overlay(Capsule().stroke(HarnessTheme.border, lineWidth: 0.5))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("切换模型提供商与模型")
    }

    private func select(provider: ModelProvider, model: String) {
        var cfg = viewModel.llmConfig
        cfg.provider = provider
        cfg.modelName = model
        if provider == .local, cfg.modelName == "local" {
            viewModel.showToast("请在「设置 → 模型服务」填写本地模型名称（如 qwen2.5:7b）")
        }
        cfg.save()
        viewModel.showToast("已切换：\(provider.displayName) / \(model)")
    }
}

// MARK: - 输入框「加号」菜单（P0.5.2：文件附件 + 插件工具入口）

//
// 插件工具 = 已注册工具注册表（内置插件工具 + MCP 服务器工具，mcp_ 前缀）。
// 选中后向输入框插入 `@toolName` 提及 token：发送后进入用户消息，
// AgentLoop 工具循环已把全部注册工具下发给 LLM，提及用于明确指定优先调用目标。

struct PlusMenuButton: View {
    let tools: [ToolDisplayItem]
    let onAttach: () -> Void
    let onInsertTool: (ToolDisplayItem) -> Void
    @State private var hovered = false

    /// 按分组（categoryDisplay）稳定排序，空分组名归入「工具」
    private var grouped: [(category: String, items: [ToolDisplayItem])] {
        let byCategory = Dictionary(grouping: tools) { $0.categoryDisplay.isEmpty ? "工具" : $0.categoryDisplay }
        return byCategory
            .sorted { $0.key < $1.key }
            .map { (category: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        Menu {
            Button(action: onAttach) {
                Label("附加文件", systemImage: "paperclip")
            }
            Divider()
            if tools.isEmpty {
                Text("暂无可用工具")
                    .font(.system(size: 12, design: .rounded))
            } else {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.items) { tool in
                            Button {
                                onInsertTool(tool)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("@\(tool.name)")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(tool.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(HarnessTheme.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .help(tool.description)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovered ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.secondary.opacity(hovered ? 0.16 : 0.08)))
                .clipShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("附加文件 / 插件工具")
    }
}
