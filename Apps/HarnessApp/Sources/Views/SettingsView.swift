import Account
import SwiftUI

// MARK: - 设置两级菜单模型

/// 一级菜单（顶级分类）
enum SettingsTab: CaseIterable, Identifiable {
    case general, llm, plugins, about

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .general: "通用"
        case .llm: "模型服务"
        case .plugins: "插件"
        case .about: "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .llm: "brain"
        case .plugins: "puzzlepiece.extension"
        case .about: "info.circle"
        }
    }

    /// 二级子页列表（侧栏在选中项下展开）
    var children: [SettingsSubTab] {
        switch self {
        case .general:
            [.preferences, .notifications, .sandbox, .account]
        case .llm:
            [.providers, .params, .connection]
        case .plugins:
            [.pluginManagement]
        case .about:
            [.about]
        }
    }

    var rootSubTab: SettingsSubTab {
        children[0]
    }
}

/// 二级子页（子页面导航/跳转的目标）
enum SettingsSubTab: CaseIterable, Identifiable, Hashable {
    case preferences, notifications, sandbox, account
    case providers, params, connection
    case pluginManagement
    case about

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .preferences: "偏好"
        case .notifications: "通知"
        case .sandbox: "文件沙箱"
        case .providers: "提供商与密钥"
        case .params: "请求参数"
        case .connection: "连接测试"
        case .account: "账号与同步"
        case .pluginManagement: "插件管理"
        case .about: "关于 Harness"
        }
    }

    var icon: String {
        switch self {
        case .preferences: "paintpalette"
        case .notifications: "bell.badge"
        case .sandbox: "lock.shield"
        case .providers: "brain"
        case .params: "cpu"
        case .connection: "link"
        case .account: "icloud"
        case .pluginManagement: "puzzlepiece.extension"
        case .about: "info.circle"
        }
    }

    var parentTab: SettingsTab {
        switch self {
        case .preferences, .notifications, .sandbox, .account: .general
        case .providers, .params, .connection: .llm
        case .pluginManagement: .plugins
        case .about: .about
        }
    }
}

/// 设置导航状态机（纯逻辑，可独立单测；视图层只做动画包装）
struct SettingsNavigationState {
    /// 当前选中的一级分类
    var selectedTab: SettingsTab = .general
    /// 子页面栈（空 = 当前分类根子页）；单级深度，至多一个子页
    var path: [SettingsSubTab] = []

    /// 当前展示的二级子页
    var currentSub: SettingsSubTab {
        path.last ?? selectedTab.rootSubTab
    }

    /// 切换一级分类：重置子页栈
    mutating func selectTab(_ tab: SettingsTab) {
        selectedTab = tab
        path = []
    }

    /// 跳转到子页：其他分类的子页忽略；根子页 = 清空栈
    mutating func selectSub(_ sub: SettingsSubTab) {
        guard sub.parentTab == selectedTab else { return }
        path = (sub == selectedTab.rootSubTab) ? [] : [sub]
    }

    /// 返回当前分类根子页
    mutating func goBack() {
        path = []
    }
}

// MARK: - 设置页（两级菜单 + 子页面导航/跳转）

struct SettingsView: View {
    /// AppViewModel（主题插件选项 / 切换；P0.4）
    var viewModel: AppViewModel
    /// 沙箱设置变更回调（由 AppViewModel 消费，重新注册工具）
    var onSandboxChange: ((String?) -> Void)?
    /// 系统通知开关变更回调（由 AppViewModel 消费，同步 NotificationCoordinator）
    var onNotificationsChange: ((Bool) -> Void)?
    /// 账号与工作区服务（P0.1；nil = 未就绪）
    var accountService: AccountService?

    /// 导航状态机（选中分类 + 子页栈）
    @State private var nav = SettingsNavigationState()
    /// P2.1 完整设置页面弹窗开关
    @State private var showCompleteSettings = false

    /// 当前选中的一级分类
    private var selectedTab: SettingsTab {
        nav.selectedTab
    }

    /// 当前展示的二级子页
    private var currentSub: SettingsSubTab {
        nav.currentSub
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentPane
        }
        .background(HarnessTheme.bgPrimary)
        // P1.1 C3：设置 sheet 同区域容器化（侧栏 .prominent 面 + 内容区 .thin 卡共存；
        // morph 仅在同变体成员间发生，异 level 成员共存合法 —— 验证文档 §六 glassEffectUnion 语义）
        .glassSurfaceContainer()
    }

    // MARK: 侧栏（一级菜单 + 选中项展开二级子项）

    private var sidebar: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        SettingsSidebarRow(tab: tab, isSelected: selectedTab == tab) {
                            selectTab(tab)
                        }
                        // 二级菜单：仅展开当前选中分类
                        if selectedTab == tab {
                            ForEach(tab.children, id: \.self) { sub in
                                SettingsSubRow(sub: sub, isSelected: currentSub == sub) {
                                    selectSub(sub)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .frame(width: 200)
        .glassSurface(.prominent, cornerRadius: 0)
    }

    // MARK: 内容区（子页头 + 子页内容）

    private var contentPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !nav.path.isEmpty {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HarnessTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回上一级设置")
                }
                Text(currentSub.title)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(HarnessTheme.textPrimary)
                Spacer()
                // 关闭设置（返回进入前的 tab；P0 实机验收：设置页无返回途径，2026-08-26）
                Button(action: closeSettings) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.08)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("关闭设置，返回上一页面")
                .accessibilityLabel("关闭设置")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // P2.1 完整设置页面（弹窗概览，作为入口横幅展示）
            Button("打开完整设置页面（账号 / iCloud / 模型 / 插件 / 记忆 / 权限 / 主题 七卡片概览）") {
                showCompleteSettings = true
            }
            .font(.system(size: 11)).foregroundStyle(HarnessTheme.accent)
            .padding(.horizontal, 16).padding(.vertical, 8)

            subPageView(currentSub)
        }
        .sheet(isPresented: $showCompleteSettings) {
            SettingsCompletePage(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func subPageView(_ sub: SettingsSubTab) -> some View {
        switch sub {
        case .preferences:
            GeneralPreferencesView(viewModel: viewModel)
        case .notifications:
            SectionSubPage {
                NotificationsSection(onNotificationsChange: onNotificationsChange)
            }
        case .sandbox:
            SectionSubPage {
                FileSandboxSection(onSandboxChange: onSandboxChange)
            }
        case .account:
            if let accountService {
                SectionSubPage {
                    AccountSyncSection(accountService: accountService, viewModel: viewModel)
                }
            } else {
                SectionSubPage {
                    Text("账号服务未就绪")
                        .foregroundStyle(HarnessTheme.textSecondary)
                }
            }
        case .providers, .params, .connection:
            // 单一容器承载模型服务三个子页（共享 LLMSettingsViewModel，切换子页不丢失未保存输入）
            LLMSettingsContainer(sub: sub)
        case .pluginManagement:
            PluginSettingsView()
        case .about:
            AboutSettingsView()
        }
    }

    // MARK: 导航动作

    private func selectTab(_ tab: SettingsTab) {
        withAnimation(.smooth) {
            nav.selectTab(tab)
        }
    }

    private func selectSub(_ sub: SettingsSubTab) {
        withAnimation(.smooth) {
            nav.selectSub(sub)
        }
    }

    private func goBack() {
        withAnimation(.smooth) {
            nav.goBack()
        }
    }

    /// 关闭设置：回到进入设置前记录的 tab（AppViewModel.settingsReturnTab）
    private func closeSettings() {
        withAnimation(.smooth) {
            viewModel.selectedTab = viewModel.settingsReturnTab
        }
    }
}

// MARK: - 侧栏行（一级）

struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? HarnessTheme.accent : HarnessTheme.textSecondary)
                    .frame(width: 20)

                Text(tab.title)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(isSelected ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.12) :
                isHovered ? HarnessTheme.surface : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 侧栏行（二级子项，缩进展示）

struct SettingsSubRow: View {
    let sub: SettingsSubTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: sub.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? HarnessTheme.accent : HarnessTheme.textTertiary)
                    .frame(width: 14)

                Text(sub.title)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(isSelected ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.leading, 14)
            .background(isSelected ? Color.blue.opacity(0.10) :
                isHovered ? HarnessTheme.surface : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 通用设置（偏好：外观 + 快捷键）

struct GeneralPreferencesView: View {
    var viewModel: AppViewModel
    @AppStorage(ThemeManager.themeKey) private var theme: String = "system"
    @AppStorage("fontSize") private var fontSize: Double = 14

    /// 主题插件选择绑定（get = 当前激活；set = 即时应用）
    private var themeSelection: Binding<String> {
        Binding(
            get: { viewModel.activeThemeSpec.id },
            set: { viewModel.applyTheme(id: $0) }
        )
    }

    /// P1.4：激活主题玻璃参数展示行（材质档位明示 = P1.1 决策「主题玻璃参数 = 材质档位 + tint」的 UI 兑现；
    /// 系统基准/未配置 = 系统默认，文案不硬编主题值（铁律 5））
    @ViewBuilder
    private var glassParamRow: some View {
        let spec = viewModel.activeThemeSpec
        if spec.glassTintHex == nil, spec.glassMaterial == nil {
            Text("玻璃：系统默认（当前主题未配置玻璃参数）")
                .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
        } else {
            HStack(spacing: 6) {
                if let tint = spec.glassTintHex.flatMap({ Color(hex: $0) }) {
                    RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(HarnessTheme.border, lineWidth: 0.5))
                }
                Text("玻璃：tint \(spec.glassTintHex ?? "无（系统默认）") · 材质档位 \(GlassSurfaceModifier.materialLabel(glassMaterial: spec.glassMaterial))")
                    .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard(title: "外观", icon: "paintpalette") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("主题")
                                .font(.system(.body))
                                .foregroundStyle(HarnessTheme.textPrimary)

                            Picker("主题", selection: $theme) {
                                Text("深色").tag("dark")
                                Text("浅色").tag("light")
                                Text("跟随系统").tag("system")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 240)
                            .onChange(of: theme) { _, newValue in
                                ThemeManager.apply(newValue)
                            }
                        }
                        Text("当前：\(theme == "dark" ? "深色" : theme == "light" ? "浅色" : "跟随系统")")
                            .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)

                        Divider()

                        HStack {
                            Text("主题插件")
                                .font(.system(.body))
                                .foregroundStyle(HarnessTheme.textPrimary)

                            Picker("主题插件", selection: themeSelection) {
                                ForEach(viewModel.themeOptions) { option in
                                    Text(option.isSystem
                                        ? option.spec.name
                                        : "\(option.spec.name) · \(option.sourceName)")
                                        .tag(option.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 300)
                        }
                        Text("主题一律来自主题插件（本地插件 / MCP 主题服务器）；卸载正在使用的主题自动回落系统基准。")
                            .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                        // P1.4：激活主题玻璃参数明示（tint 色板 + 材质档位；解析与渲染同一纯函数单点）
                        glassParamRow

                        HStack {
                            Text("正文字号")
                                .font(.system(.body))
                                .foregroundStyle(HarnessTheme.textPrimary)

                            Slider(value: $fontSize, in: 12 ... 24) {
                                Text("正文字号")
                            }
                            .labelsHidden()
                            .frame(width: 200)
                            Text("\(Int(fontSize))pt").font(.system(size: 12)).foregroundStyle(HarnessTheme.textSecondary)
                        }
                    }
                }

                SettingsCard(title: "快捷键", icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 8) {
                        ShortcutRow(keys: "Enter", action: "发送消息")
                        ShortcutRow(keys: "Shift + Enter", action: "换行")
                    }
                }
            }
            .padding(20)
        }
        .background(HarnessTheme.bgPrimary)
    }
}

struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassSurface(.thin, cornerRadius: 4)
                .frame(width: 110, alignment: .leading)

            Text(action)
                .font(.system(size: 13))
                .foregroundStyle(HarnessTheme.textSecondary)

            Spacer()
        }
    }
}

// MARK: - 子页容器（单卡片子页的通用滚动容器）

struct SectionSubPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(20)
        }
        .background(HarnessTheme.bgPrimary)
    }
}

// MARK: - 设置卡片

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(HarnessTheme.accent)
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
            }

            content()
        }
        .padding(16)
        .background(isHovered ? HarnessTheme.surfaceHover : HarnessTheme.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(HarnessTheme.border, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }
}
