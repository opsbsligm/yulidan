import LLM
import ServiceContainer
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = SettingsTab.general
    /// 沙箱设置变更回调（由 AppViewModel 消费，重新注册工具）
    var onSandboxChange: ((String?) -> Void)?
    /// 系统通知开关变更回调（由 AppViewModel 消费，同步 NotificationCoordinator）
    var onNotificationsChange: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // 侧栏
            VStack(spacing: 0) {
                Text("设置")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.smooth) { selectedTab = tab }
                    }
                }

                Spacer()
            }
            .frame(width: 180)
            .background(HarnessTheme.sidebarBg)

            Divider()

            // 内容
            switch selectedTab {
            case .general:
                GeneralSettingsView(onSandboxChange: onSandboxChange,
                                    onNotificationsChange: onNotificationsChange)
            case .llm:
                LLMSettingsView()
            case .plugins:
                PluginSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .background(HarnessTheme.bgPrimary)
    }
}

// MARK: - 侧栏行

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
    }
}

// MARK: - 设置页签

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
}

// MARK: - 通用设置

struct GeneralSettingsView: View {
    @AppStorage(ThemeManager.themeKey) private var theme: String = "system"
    @AppStorage("fontSize") private var fontSize: Double = 14
    var onSandboxChange: ((String?) -> Void)?
    var onNotificationsChange: ((Bool) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("通用").font(.system(.title3, design: .rounded)).fontWeight(.semibold)

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
                            .frame(width: 240)
                            .onChange(of: theme) { _, newValue in
                                ThemeManager.apply(newValue)
                            }
                        }
                        Text("当前：\(theme == "dark" ? "深色" : theme == "light" ? "浅色" : "跟随系统")")
                            .font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)

                        HStack {
                            Text("正文字号")
                                .font(.system(.body))
                                .foregroundStyle(HarnessTheme.textPrimary)

                            Slider(value: $fontSize, in: 12 ... 24) {
                                Text("正文字号: \(Int(fontSize))pt")
                            }
                            .frame(width: 200)
                            Text("\(Int(fontSize))pt").font(.system(size: 12)).foregroundStyle(HarnessTheme.textSecondary)
                        }
                    }
                }

                NotificationsSection(onNotificationsChange: onNotificationsChange)

                FileSandboxSection(onSandboxChange: onSandboxChange)

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
                .background(HarnessTheme.surface)
                .cornerRadius(4)
                .frame(width: 110, alignment: .leading)

            Text(action)
                .font(.system(size: 13))
                .foregroundStyle(HarnessTheme.textSecondary)

            Spacer()
        }
    }
}

// MARK: - 模型服务设置（真实 LLM 配置 + 真实连接测试）

struct LLMSettingsView: View {
    @StateObject private var viewModel = LLMSettingsViewModel()
    @State private var showSaveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("模型服务").font(.system(.title3, design: .rounded)).fontWeight(.semibold)

                // 提供商选择
                SettingsCard(title: "提供商", icon: "brain") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择 AI 模型提供商")
                            .font(.system(size: 13))
                            .foregroundStyle(HarnessTheme.textSecondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 10) {
                            ForEach(ModelProvider.allCases, id: \.self) { provider in
                                ProviderCard(
                                    provider: provider,
                                    isSelected: viewModel.selectedProvider == provider,
                                    hasKey: viewModel.hasKey(for: provider)
                                ) {
                                    viewModel.selectProvider(provider)
                                }
                            }
                        }
                    }
                }

                // API Key
                SettingsCard(title: "API Key", icon: "key") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("当前提供商")
                                .foregroundStyle(HarnessTheme.textSecondary)
                            Spacer()
                            Text(viewModel.selectedProvider.displayName)
                                .foregroundStyle(HarnessTheme.textPrimary)
                        }

                        HStack(spacing: 10) {
                            SecureField(viewModel.selectedProvider == .local ? "本地服务通常无需 Key，可留空" : "API Key", text: $viewModel.apiKey)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)

                            Button(viewModel.hasKey(for: viewModel.selectedProvider) ? "更新" : "保存") {
                                viewModel.save()
                                showSaveConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)

                            if viewModel.hasKey(for: viewModel.selectedProvider) {
                                Button("清除") {
                                    viewModel.clearAPIKey()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 11))
                            Text("API Key 安全存储在 macOS 钥匙串中，不会明文落盘")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(HarnessTheme.textTertiary)
                    }
                }

                // 模型配置
                SettingsCard(title: "模型", icon: "cpu") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("模型名称")
                            Spacer()
                            TextField(viewModel.selectedProvider == .local ? "如 qwen2.5:7b / llama3.2" : "模型 ID", text: $viewModel.modelName)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 250)
                        }

                        if viewModel.selectedProvider == .local {
                            HStack {
                                Text("服务地址")
                                Spacer()
                                TextField("OpenAI 兼容端点", text: $viewModel.localBaseURL)
                                    .font(.system(.body, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 300)
                            }
                        }

                        HStack {
                            Text("最大 Token 数")
                            Spacer()
                            Text("\(Int(viewModel.maxTokens))")
                                .foregroundStyle(HarnessTheme.textSecondary)
                        }
                        Slider(value: $viewModel.maxTokens, in: 256 ... 8192, step: 256) {
                            Text("最大 Token 数")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("系统提示词")
                                .font(.system(size: 12)).foregroundStyle(HarnessTheme.textSecondary)
                            TextEditor(text: $viewModel.systemPrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 70)
                                .padding(4)
                                .background(HarnessTheme.surface).cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(HarnessTheme.border, lineWidth: 0.5))
                        }
                    }
                }

                // 连接测试（真实 HTTP 探测）
                SettingsCard(title: "连接测试", icon: "link") {
                    HStack(spacing: 14) {
                        Button(
                            action: { viewModel.testConnection() },
                            label: {
                                HStack(spacing: 6) {
                                    if viewModel.isTesting {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                    Text(viewModel.isTesting ? "测试中…" : "测试连接")
                                }
                            }
                        )
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isTesting)

                        if let result = viewModel.testResult {
                            HStack(spacing: 6) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? .green : .red)
                                Text(result.message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(result.success ? .green : .red)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(20)
        }
        .background(HarnessTheme.bgPrimary)
        .alert("已保存", isPresented: $showSaveConfirmation) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("配置已保存，API Key 已写入 macOS 钥匙串，对话将立即使用新配置。")
        }
    }
}

struct ProviderCard: View {
    let provider: ModelProvider
    let isSelected: Bool
    let hasKey: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.15) : HarnessTheme.surface)
                        .frame(width: 40, height: 40)

                    Image(systemName: provider.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? HarnessTheme.accent : HarnessTheme.textSecondary)
                }

                Text(provider.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)

                HStack(spacing: 4) {
                    if provider == .local || hasKey {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(provider == .local ? "本地服务" : "已配置 Key")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else {
                        Text("未配置 Key")
                            .font(.system(size: 10))
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.08) :
                isHovered ? HarnessTheme.surface : .clear)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? HarnessTheme.accent : HarnessTheme.border, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - 模型服务 ViewModel（与主 ViewModel 共享 LLMConfig）

@MainActor
final class LLMSettingsViewModel: ObservableObject {
    @Published var selectedProvider: ModelProvider
    @Published var apiKey: String = ""
    @Published var modelName: String
    @Published var maxTokens: Double
    @Published var localBaseURL: String
    @Published var systemPrompt: String
    @Published var isTesting = false
    @Published var testResult: (success: Bool, message: String)?

    private var testTask: Task<Void, Never>?

    init() {
        let cfg = LLMConfig.load()
        selectedProvider = cfg.provider
        modelName = cfg.modelName
        maxTokens = Double(cfg.maxTokens)
        localBaseURL = cfg.localBaseURL
        systemPrompt = cfg.systemPrompt
        apiKey = KeychainStorage.getAPIKey(forProvider: cfg.providerRaw) ?? ""
    }

    func hasKey(for provider: ModelProvider) -> Bool {
        if provider == .local {
            return true
        }
        return KeychainStorage.getAPIKey(forProvider: provider.rawValue) != nil
    }

    func selectProvider(_ provider: ModelProvider) {
        selectedProvider = provider
        if modelName.isEmpty || modelName == "local" {
            modelName = provider.defaultModel
        }
        apiKey = KeychainStorage.getAPIKey(forProvider: provider.rawValue) ?? ""
    }

    /// 保存：非敏感配置 → LLMConfig(UserDefaults)；API Key → Keychain
    func save() {
        var cfg = LLMConfig.load()
        cfg.provider = selectedProvider
        cfg.modelName = modelName
        cfg.maxTokens = Int(maxTokens)
        cfg.localBaseURL = localBaseURL
        cfg.systemPrompt = systemPrompt
        if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            KeychainStorage.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces),
                                       forProvider: selectedProvider.rawValue)
        }
        cfg.save()
    }

    func clearAPIKey() {
        KeychainStorage.deleteAPIKey(forProvider: selectedProvider.rawValue)
        apiKey = ""
    }

    /// 真实连接测试
    func testConnection() {
        testTask?.cancel()
        isTesting = true
        testResult = nil
        testTask = Task { [weak self] in
            guard let self else { return }
            let key = apiKey.trimmingCharacters(in: .whitespaces)
            let provider: any LLMProvider
            switch selectedProvider {
            case .openAI: provider = OpenAIAdapter(apiKey: key)
            case .deepSeek: provider = DeepSeekAdapter(apiKey: key)
            case .anthropic: provider = AnthropicAdapter(apiKey: key)
            case .local:
                let base = URL(string: localBaseURL) ?? URL(string: "http://localhost:11434/v1")!
                provider = LocalAdapter(apiKey: key.isEmpty ? "local" : key, baseURL: base)
            }
            do {
                let msg = try await provider.checkConnection()
                if Task.isCancelled {
                    return
                }
                isTesting = false
                testResult = (true, "\(selectedProvider.displayName)：\(msg)")
            } catch {
                if Task.isCancelled {
                    return
                }
                isTesting = false
                let desc = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                testResult = (false, "连接失败：\(desc)")
            }
        }
    }
}

// MARK: - 插件设置

struct PluginSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("插件").font(.system(.title3, design: .rounded)).fontWeight(.semibold)

                SettingsCard(title: "插件管理", icon: "puzzlepiece.extension") {
                    Text("插件的启用 / 停用请前往左侧「插件」标签页。插件由 PluginManager 统一管理生命周期。")
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .background(HarnessTheme.bgPrimary)
    }
}

// MARK: - 关于

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("关于 Harness").font(.system(.title3, design: .rounded)).fontWeight(.semibold)

                SettingsCard(title: "版本", icon: "info.circle") {
                    Text("Harness v0.2.0（Swift 原生复刻 deepseek-harness）")
                        .font(.system(.body, design: .monospaced))
                }

                SettingsCard(title: "架构", icon: "doc.badge.gear") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("macOS 原生（SwiftUI + AppKit）")
                        Text("Swift 6.0 + Actor 并发隔离")
                        Text("GRDB.swift 会话持久化")
                        Text("Swift Package Manager 模块化")
                        Text("真实 LLM API / PluginManager / ToolRegistry")
                    }
                    .font(.system(size: 13))
                }

                SettingsCard(title: "开源许可", icon: "doc.text") {
                    Text("MIT License")
                        .font(.system(.body))
                }
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
