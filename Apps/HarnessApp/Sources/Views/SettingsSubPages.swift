import LLM
import ServiceContainer
import SwiftUI

// MARK: - 模型服务子页容器（三个子页共享 ViewModel，切换子页不丢失未保存输入）

struct LLMSettingsContainer: View {
    let sub: SettingsSubTab
    @StateObject private var viewModel = LLMSettingsViewModel()
    @State private var showSaveConfirmation = false

    /// 常用预设按钮标签（8K/128K/256K/1M）
    static func tokenPresetLabel(_ v: Int) -> String {
        switch v {
        case 8192: "8K"
        case 16384: "16K"
        case 32768: "32K"
        case 65536: "64K"
        case 131_072: "128K"
        case 262_144: "256K"
        case 1_048_576: "1M"
        default: "\(v)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch sub {
                case .providers:
                    providerSection
                case .params:
                    modelSection
                case .connection:
                    connectionSection
                default:
                    EmptyView()
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

    /// 子页：提供商与密钥
    @ViewBuilder
    private var providerSection: some View {
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

        SettingsCard(title: "API Key", icon: "key") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("当前提供商")
                        .font(.system(size: 13))
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
                    .buttonStyle(.glassProminent) // P1.1 C5：密钥保存/更新（表单确认）→ 玻璃强调

                    if viewModel.hasKey(for: viewModel.selectedProvider) {
                        Button("清除") {
                            viewModel.clearAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }

                HStack {
                    Text("API 地址")
                    Spacer()
                    TextField(viewModel.apiBasePlaceholder, text: $viewModel.apiBaseURLText)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                        .onSubmit { viewModel.save() }
                }
                Text(viewModel.apiBaseHint)
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textTertiary)
                if let error = viewModel.paramError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.error)
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
    }

    /// 子页：请求参数
    private var modelSection: some View {
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

                HStack(spacing: 8) {
                    Text("最大 Token 数")
                    Spacer()
                    TextField("如 4096 / 262144 / 1048576", text: $viewModel.maxTokensText)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .onSubmit { viewModel.save() }
                    ForEach([8192, 131_072, 262_144, 1_048_576], id: \.self) { v in
                        Button(Self.tokenPresetLabel(v)) {
                            viewModel.maxTokensText = "\(v)"
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                }
                Text("范围 \(LLMConfig.maxTokensRange.lowerBound) – \(LLMConfig.maxTokensRange.upperBound)（1M）；保存时校验，越界不保存")
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textTertiary)

                HStack(spacing: 8) {
                    Text("上下文大小")
                    Spacer()
                    TextField("留空 = 跟随模型默认", text: $viewModel.contextWindowText)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .onSubmit { viewModel.save() }
                    ForEach([8192, 16384, 32768, 65536, 131_072, 262_144, 1_048_576], id: \.self) { v in
                        Button(Self.tokenPresetLabel(v)) {
                            viewModel.contextWindowText = "\(v)"
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                }
                Text("范围 \(LLMConfig.contextWindowRange.lowerBound) – \(LLMConfig.contextWindowRange.upperBound)（1M）；仅 Ollama 本地模型生效（原生 API options.num_ctx 真实下发）；远程提供商与 vLLM/LM Studio 忽略")
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textTertiary)

                HStack {
                    Text("思考等级")
                    Spacer()
                    Picker("", selection: $viewModel.thinkingLevel) {
                        ForEach(ThinkingLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                Text(viewModel.thinkingHint)
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textTertiary)
                if let error = viewModel.paramError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.error)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("系统提示词")
                        .font(.system(size: 12)).foregroundStyle(HarnessTheme.textSecondary)
                    TextEditor(text: $viewModel.systemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 70)
                        .padding(4)
                        .glassSurface(.thin, cornerRadius: 6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(HarnessTheme.border, lineWidth: 0.5))
                }

                Button("保存参数") {
                    viewModel.save()
                    showSaveConfirmation = true
                }
                .buttonStyle(.glassProminent) // P1.1 C5：保存参数（表单确认）→ 玻璃强调
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// 子页：连接测试
    private var connectionSection: some View {
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
}

// MARK: - 提供商卡片

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

// MARK: - 插件设置（子页）

struct PluginSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

// MARK: - 关于（子页）

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

// MARK: - 模型服务 ViewModel（与主 ViewModel 共享 LLMConfig）

@MainActor
final class LLMSettingsViewModel: ObservableObject {
    @Published var selectedProvider: ModelProvider
    @Published var apiKey: String = ""
    @Published var modelName: String
    @Published var maxTokensText: String
    @Published var contextWindowText: String
    @Published var apiBaseURLText: String
    @Published var thinkingLevel: ThinkingLevel
    @Published var systemPrompt: String
    @Published var isTesting = false
    @Published var testResult: (success: Bool, message: String)?
    /// 参数校验错误（maxTokens 非整数/越界时非 nil；两个子页都展示）
    @Published var paramError: String?

    private var testTask: Task<Void, Never>?

    init() {
        let cfg = LLMConfig.load()
        selectedProvider = cfg.provider
        modelName = cfg.modelName
        maxTokensText = "\(cfg.maxTokens)"
        contextWindowText = cfg.contextWindow.map { "\($0)" } ?? ""
        apiBaseURLText = cfg.provider == .local ? cfg.localBaseURL : (cfg.baseURLOverride ?? "")
        thinkingLevel = cfg.thinkingLevel
        systemPrompt = cfg.systemPrompt
        apiKey = KeychainStorage.getAPIKey(forProvider: cfg.providerRaw) ?? ""
    }

    /// API 地址输入占位（local = 本地端点示例；其他 = 官方默认地址）
    var apiBasePlaceholder: String {
        selectedProvider == .local ? "如 http://localhost:11434/v1" : selectedProvider.baseURL.absoluteString
    }

    /// API 地址说明
    var apiBaseHint: String {
        selectedProvider == .local
            ? "OpenAI 兼容端点（Ollama / vLLM / LM Studio）"
            : "留空 = 使用官方默认地址 \(selectedProvider.baseURL.absoluteString)"
    }

    /// 思考等级说明（按提供商能力诚实标注）
    var thinkingHint: String {
        switch selectedProvider {
        case .anthropic:
            "Anthropic 使用独立 thinking 机制（budget_tokens），暂未接入；此项不下发"
        case .openAI where !ThinkingLevel.openAIApplies(toModel: modelName):
            "仅 o1/o3/o4/gpt-5 系推理模型会下发 reasoning_effort；当前模型（\(modelName)）不会下发"
        case .openAI:
            "low/medium/high → 下发 reasoning_effort；关 = 不下发，跟随模型默认"
        case .deepSeek:
            "low/medium/high → 下发 reasoning_effort（官方：medium 映射 high，默认 high）；关 = 不下发"
        case .local:
            "low/medium/high → 下发 Ollama（官方：仅思考模型生效，如 qwen3 系）；关 = 不下发"
        }
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
        let cfg = LLMConfig.load()
        apiBaseURLText = provider == .local ? cfg.localBaseURL : (cfg.baseURLOverride ?? "")
    }

    /// 解析 + 校验 maxTokens 输入（nil = 非法）
    func parsedMaxTokens() -> Int? {
        let v = Int(maxTokensText.trimmingCharacters(in: .whitespaces))
        guard let v, LLMConfig.maxTokensRange.contains(v) else { return nil }
        return v
    }

    /// 保存：非敏感配置 → LLMConfig(UserDefaults)；API Key → Keychain
    /// maxTokens 非法时保留原值、不写入（并展示错误），其余字段照常保存
    func save() {
        var cfg = LLMConfig.load()
        cfg.provider = selectedProvider
        cfg.modelName = modelName
        if let v = parsedMaxTokens() {
            cfg.maxTokens = v
            paramError = nil
        } else {
            paramError = "最大 Token 数须为 \(LLMConfig.maxTokensRange.lowerBound) – \(LLMConfig.maxTokensRange.upperBound) 的整数（本次未更新该项，其余已保存）"
        }
        let base = apiBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedProvider == .local {
            cfg.localBaseURL = base.isEmpty ? "http://localhost:11434/v1" : base
        } else {
            cfg.baseURLOverride = base.isEmpty ? nil : base
        }
        cfg.thinkingLevel = thinkingLevel
        let cwRaw = contextWindowText.trimmingCharacters(in: .whitespaces)
        if cwRaw.isEmpty {
            cfg.contextWindow = nil // 留空 = 显式回落到跟随模型默认
        } else if let v = Int(cwRaw), LLMConfig.contextWindowRange.contains(v) {
            cfg.contextWindow = v
        } else if paramError == nil {
            // 非法值保留原值不写入；maxTokens 已有报错时不覆盖错误展示
            paramError = "上下文大小须为 \(LLMConfig.contextWindowRange.lowerBound) – \(LLMConfig.contextWindowRange.upperBound) 的整数或留空（跟随模型默认）；本次未更新该项，其余已保存"
        }
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
            // 与真实调用同路：覆盖值优先的生效地址
            var testCfg = LLMConfig.load()
            testCfg.provider = selectedProvider
            let base = apiBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedProvider == .local {
                testCfg.localBaseURL = base.isEmpty ? "http://localhost:11434/v1" : base
            } else {
                testCfg.baseURLOverride = base.isEmpty ? nil : base
            }
            let url = testCfg.provider.effectiveBaseURL(testCfg)
            let provider: any LLMProvider = switch selectedProvider {
            case .openAI: OpenAIAdapter(apiKey: key, baseURL: url)
            case .deepSeek: DeepSeekAdapter(apiKey: key, baseURL: url)
            case .anthropic: AnthropicAdapter(apiKey: key, baseURL: url)
            case .local:
                LocalAdapter(apiKey: key.isEmpty ? "local" : key, baseURL: url)
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
