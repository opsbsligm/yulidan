import ServiceContainer
import SwiftUI

struct PluginListView: View {
    enum PluginPane: String, CaseIterable, Identifiable {
        case installed = "已安装"
        case marketplace = "插件市场"
        case mcpServers = "MCP 服务器"
        var id: String {
            rawValue
        }
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var searchText = ""
    @State private var selectedPluginId: String?
    @State private var pane: PluginPane = .installed

    // P0.4 MCP stdio 导入表单（本地态；保存时下发 AppViewModel.importMCPServer）
    @State private var mcpFormName = ""
    @State private var mcpFormCommand = ""
    @State private var mcpFormArguments = ""
    @State private var mcpFormEnvironment = ""
    /// P0.4 运行日志面板（非 nil = 展示日志 sheet）
    @State private var logServer: MCPDisplayItem?

    var filteredMarket: [MarketplaceDisplayItem] {
        if searchText.isEmpty {
            return viewModel.marketplaceEntries
        }
        return viewModel.marketplaceEntries.filter { $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var subtitle: String {
        if pane == .marketplace {
            let installable = viewModel.marketplaceEntries.filter { !$0.isInstalled && $0.incompatibleReason == nil }.count
            return "\(viewModel.marketplaceEntries.count) 个目录条目，\(installable) 个可安装（本地目录源 · 真实安装）"
        }
        if pane == .mcpServers {
            let online = viewModel.mcpServers.filter(\.isAvailable).count
            return "\(online) / \(viewModel.mcpServers.count) 在线（本地 stdio 服务器 · servers.json）"
        }
        return "\(activeCount) / \(viewModel.plugins.count) 已启用（来自 PluginManager 实时状态）"
    }

    var filtered: [PluginDisplayItem] {
        if searchText.isEmpty {
            return viewModel.plugins
        }
        return viewModel.plugins.filter { $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredMCPServers: [MCPDisplayItem] {
        if searchText.isEmpty {
            return viewModel.mcpServers
        }
        return viewModel.mcpServers.filter { $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var activeCount: Int {
        viewModel.plugins.filter(\.isActive).count
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("插件").font(.system(.title2, design: .rounded)).fontWeight(.semibold)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(HarnessTheme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $pane) {
                        ForEach(PluginPane.allCases) { pane in
                            Text(pane.rawValue).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    if pane == .mcpServers {
                        Button {
                            viewModel.showMCPImportForm.toggle()
                        } label: {
                            Label("导入 MCP 服务器…", systemImage: "plus.circle").font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11))
                            .foregroundStyle(HarnessTheme.textTertiary)
                        TextField(pane == .marketplace ? "搜索市场…" : pane == .mcpServers ? "搜索 MCP…" : "搜索插件…",
                                  text: $searchText)
                            .font(.system(size: 13))
                            .textFieldStyle(.plain).disableAutocorrection(true)
                    }
                    .frame(width: 200).padding(8)
                    .background(HarnessTheme.surface).cornerRadius(8)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                Divider()
                // P0.4 权限裁决横幅（优先级最高）
                if let pending = viewModel.pendingPermissionInstall {
                    NavPermissionBanner(name: pending.name, version: pending.version,
                                        permissions: pending.permissions) {
                        Task { await viewModel.grantPendingPermissionInstall() }
                    } onDeny: {
                        viewModel.denyPendingPermissionInstall()
                    }
                    Divider()
                }
                // 加载状态（P0.3 异常 UI：失败横幅 / 部分失败警告）
                if case let .failed(msg) = viewModel.pluginsLoadState {
                    NavErrorBanner(message: msg) {
                        Task { await viewModel.retryLoadPlugins() }
                    }
                    Divider()
                } else if let warning = viewModel.pluginsLoadWarning {
                    NavWarningBanner(message: warning)
                    Divider()
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if pane == .installed {
                            ForEach(filtered, id: \.id) { plugin in
                                PluginCard(plugin: plugin,
                                           isolated: viewModel.isolatedPluginIDs.contains(plugin.id)) {
                                    viewModel.togglePlugin(plugin)
                                }
                                .onTapGesture {
                                    selectedPluginId = (selectedPluginId == plugin.id) ? nil : plugin.id
                                }
                            }
                            if filtered.isEmpty {
                                if viewModel.pluginsLoadState.isLoading {
                                    NavLoadingView().padding(.vertical, 40)
                                } else {
                                    ContentUnavailableView("未找到插件", systemImage: "puzzlepiece.extension",
                                                           description: Text("尝试其他搜索词")).padding(.top, 40)
                                }
                            }
                        } else if pane == .marketplace {
                            ForEach(filteredMarket, id: \.id) { item in
                                MarketplaceCard(
                                    item: item,
                                    onInstall: { viewModel.installFromMarket(item) },
                                    onUpdate: { viewModel.updateFromMarket(item) },
                                    onUninstall: { viewModel.uninstallFromMarket(item) }
                                )
                            }
                            if filteredMarket.isEmpty {
                                ContentUnavailableView("未找到插件", systemImage: "shippingbox",
                                                       description: Text("尝试其他搜索词")).padding(.top, 40)
                            }
                        } else {
                            if viewModel.showMCPImportForm {
                                mcpImportForm
                                Divider()
                            }
                            ForEach(filteredMCPServers, id: \.id) { server in
                                MCPServerRow(server: server) {
                                    Task { await viewModel.retryMCPServer(server) }
                                } onLogs: {
                                    logServer = server
                                } onRemove: {
                                    Task { await viewModel.removeMCPServer(server) }
                                }
                            }
                            if filteredMCPServers.isEmpty, !viewModel.showMCPImportForm {
                                ContentUnavailableView("暂无 MCP 服务器", systemImage: "server.rack",
                                                       description: Text("点击「导入 MCP 服务器…」添加本地 stdio 服务"))
                                    .padding(.top, 40)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            if pane == .installed, let id = selectedPluginId, let plugin = viewModel.plugins.first(where: { $0.id == id }) {
                Divider().frame(height: 1)
                PluginDetailView(viewModel: viewModel, plugin: plugin).frame(minWidth: 280, maxWidth: 340)
            }
        }
        .background(HarnessTheme.bgPrimary)
        .task(id: pane) {
            if pane == .mcpServers {
                await viewModel.refreshMCPServers()
            } else {
                await viewModel.refreshMarketplace()
            }
        }
        .onChange(of: pane) { _, _ in
            selectedPluginId = nil
        }
        .sheet(item: $logServer) { server in
            MCPServerLogSheet(viewModel: viewModel, server: server)
        }
    }

    // MARK: P0.4 MCP stdio 导入表单

    private var mcpImportForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("名称（唯一标识，如 filesystem）", text: $mcpFormName)
                    .font(.system(size: 13))
                    .textFieldStyle(.roundedBorder)
                TextField("命令（绝对路径优先，如 /usr/bin/npx）", text: $mcpFormCommand)
                    .font(.system(size: 13))
                    .textFieldStyle(.roundedBorder)
            }
            TextField("启动参数（空格分隔，如 -y @modelcontextprotocol/server-filesystem /tmp）",
                      text: $mcpFormArguments)
                .font(.system(size: 13))
                .textFieldStyle(.roundedBorder)
            TextField("环境变量（K=V 空格分隔，可留空）", text: $mcpFormEnvironment)
                .font(.system(size: 13))
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("写入 \(viewModel.mcpConfigURL.path)（同名 = 更新）")
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textSecondary)
                Spacer()
                Button("取消") {
                    viewModel.showMCPImportForm = false
                }
                Button("导入并连接") {
                    let (name, command, arguments, environment) =
                        (mcpFormName, mcpFormCommand, mcpFormArguments, mcpFormEnvironment)
                    clearMCPForm()
                    Task {
                        await viewModel.importMCPServer(name: name, command: command,
                                                        arguments: arguments, environment: environment)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mcpFormName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    mcpFormCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func clearMCPForm() {
        mcpFormName = ""
        mcpFormCommand = ""
        mcpFormArguments = ""
        mcpFormEnvironment = ""
    }
}

struct PluginCard: View {
    let plugin: PluginDisplayItem
    var isolated: Bool = false
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(plugin.isActive ? Color.green.opacity(0.12) : HarnessTheme.surface)
                    .frame(width: 36, height: 36)
                Image(systemName: plugin.isActive ? "puzzlepiece.extension.fill" : "puzzlepiece.extension")
                    .font(.system(size: 16))
                    .foregroundStyle(plugin.isActive ? .green : HarnessTheme.textTertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(plugin.name).font(.system(.body, design: .rounded)).fontWeight(.medium)
                    Text("v\(plugin.version)").font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                    if isolated {
                        Text("隔离").font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15)).cornerRadius(3)
                            .foregroundStyle(.purple)
                    }
                    if plugin.isTheme {
                        Text("主题").font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.pink.opacity(0.15)).cornerRadius(3)
                            .foregroundStyle(.pink)
                    }
                    Spacer()
                    StateBadge(state: plugin.state)
                }
                Text(plugin.description).font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.textSecondary).lineLimit(2)
                HStack(spacing: 4) {
                    ForEach(plugin.permissions.prefix(3), id: \.self) { perm in
                        Text(perm).font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15)).cornerRadius(3)
                            .foregroundStyle(Color.orange)
                    }
                    if plugin.permissions.count > 3 {
                        Text("+\(plugin.permissions.count - 3)").font(.system(size: 9))
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                }
            }
            Spacer()
            // 真实开关：调用 PluginManager install/uninstall
            Toggle("", isOn: Binding(
                get: { plugin.isActive },
                set: { _ in onToggle() }
            )).labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(plugin.state == .loading || plugin.state == .initializing ||
                    plugin.state == .starting || plugin.state == .stopping)
        }
        .padding(12)
        .background(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.4) : HarnessTheme.surface.opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isHovered ? HarnessTheme.accent.opacity(0.3) : HarnessTheme.border, lineWidth: 0.5))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

struct StateBadge: View {
    let state: PluginState
    var color: Color {
        switch state {
        case .active: .green
        case .stopped: .gray
        case .failed, .errored: .red
        case .loading, .initializing, .starting, .stopping: .orange
        }
    }

    var label: String {
        switch state {
        case .active: "运行中"
        case .stopped: "已停用"
        case .failed: "失败"
        case .errored: "错误"
        case .loading: "加载中"
        case .initializing: "初始化"
        case .starting: "启动中"
        case .stopping: "停止中"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11)).foregroundStyle(color)
        }
    }
}

struct PluginDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let plugin: PluginDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("插件详情").font(.system(.headline, design: .rounded)).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "名称", value: plugin.name)
                DetailRow(label: "版本", value: "v\(plugin.version)")
                DetailRow(label: "状态", value: plugin.state == .active ? "运行中" : "已停用")
                DetailRow(label: "作者", value: plugin.author ?? "未知")
            }
            Divider()
            Text("描述").font(.system(.caption, design: .rounded)).fontWeight(.semibold)
                .foregroundStyle(HarnessTheme.textSecondary)
            Text(plugin.description).font(.system(size: 13)).foregroundStyle(HarnessTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("权限").font(.system(.caption, design: .rounded)).fontWeight(.semibold)
                .foregroundStyle(HarnessTheme.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(plugin.permissions, id: \.self) { perm in
                    HStack(spacing: 6) {
                        Image(systemName: "shield.check").font(.system(size: 10)).foregroundStyle(Color.orange)
                        Text(perm).font(.system(size: 12, design: .monospaced))
                    }
                }
                if plugin.permissions.isEmpty {
                    Text("无需特殊权限").font(.system(size: 12)).foregroundStyle(HarnessTheme.textTertiary).italic()
                }
            }
            // P0.4⑤：依赖（缺失红色标注）
            if !plugin.dependencies.isEmpty {
                Divider()
                Text("依赖").font(.system(.caption, design: .rounded)).fontWeight(.semibold)
                    .foregroundStyle(HarnessTheme.textSecondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plugin.dependencies, id: \.self) { dep in
                        HStack(spacing: 6) {
                            let missing = plugin.missingDependencies.contains(dep)
                            Image(systemName: missing ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(missing ? Color.red : Color.green)
                            Text(dep).font(.system(size: 12, design: .monospaced))
                            if missing {
                                Text("未安装 / 版本不满足").font(.system(size: 11)).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            Divider()
            Text("进程模型").font(.system(.caption, design: .rounded)).fontWeight(.semibold)
                .foregroundStyle(HarnessTheme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.isolatedPluginIDs.contains(plugin.id)
                    ? "独立 worker 进程运行（XPC 崩溃隔离）"
                    : "主进程内运行（Actor 隔离）")
                    .font(.system(size: 12)).foregroundStyle(HarnessTheme.textPrimary)
                Button(
                    viewModel.isolatedPluginIDs.contains(plugin.id) ? "恢复进程内运行" : "启用进程隔离",
                    action: { viewModel.toggleIsolation(for: plugin) }
                )
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Divider()
            Text("说明").font(.system(.caption, design: .rounded)).fontWeight(.semibold)
                .foregroundStyle(HarnessTheme.textSecondary)
            Text("该插件由 PluginManager 统一管理生命周期，启用/停用会真实调用 install / uninstall 流程。")
                .font(.system(size: 12)).foregroundStyle(HarnessTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HarnessTheme.sidebarBg)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(HarnessTheme.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced))
        }
    }
}

struct MarketplaceCard: View {
    let item: MarketplaceDisplayItem
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    @State private var isHovered = false

    private var hasHighRisk: Bool {
        item.permissions.contains { ["Shell 执行", "终端访问", "子进程创建", "屏幕捕获"].contains($0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.isInstalled ? Color.green.opacity(0.12) : HarnessTheme.surface)
                    .frame(width: 36, height: 36)
                Image(systemName: item.isInstalled ? "puzzlepiece.extension.fill" : "shippingbox")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isInstalled ? .green : HarnessTheme.textTertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(.body, design: .rounded)).fontWeight(.medium)
                    Text("v\(item.version)").font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                    if item.isInstalled {
                        Text("已安装").font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15)).cornerRadius(3)
                            .foregroundStyle(.green)
                    }
                    if item.hasUpdate {
                        Text("可更新").font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15)).cornerRadius(3)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    if let reason = item.incompatibleReason {
                        Text("不兼容：\(reason)").font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
                    } else {
                        actionButtons
                    }
                }
                Text(item.description).font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.textSecondary).lineLimit(2)
                HStack(spacing: 4) {
                    if hasHighRisk {
                        Text("高风险权限").font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15)).cornerRadius(3)
                            .foregroundStyle(.red)
                    }
                    ForEach(item.permissions.prefix(3), id: \.self) { perm in
                        Text(perm).font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15)).cornerRadius(3)
                            .foregroundStyle(Color.orange)
                    }
                    if item.permissions.count > 3 {
                        Text("+\(item.permissions.count - 3)").font(.system(size: 9))
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                }
                // P0.4⑤：依赖缺失红色提示 / 依赖满足灰色标注
                if !item.missingDependencies.isEmpty {
                    Text("缺少依赖：\(item.missingDependencies.joined(separator: "、"))（请先安装）")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if !item.dependencies.isEmpty {
                    Text("依赖：\(item.dependencies.joined(separator: "、"))")
                        .font(.system(size: 10))
                        .foregroundStyle(HarnessTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(12)
        .background(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.4) : HarnessTheme.surface.opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isHovered ? HarnessTheme.accent.opacity(0.3) : HarnessTheme.border, lineWidth: 0.5))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if item.hasUpdate {
                Button("更新", action: onUpdate).buttonStyle(.bordered).controlSize(.small)
            }
            if item.isInstalled {
                Button("卸载", action: onUninstall).buttonStyle(.bordered).controlSize(.small)
            } else {
                Button("安装", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!item.missingDependencies.isEmpty)
                    .help(item.missingDependencies.isEmpty ? "" : "缺少依赖插件，无法安装")
            }
        }
    }
}
