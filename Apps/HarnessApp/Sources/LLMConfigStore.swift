import Foundation
import LLM

/// 非敏感 LLM 配置（提供商/模型/参数）— UserDefaults 存储
/// 敏感的 API Key 仍走 KeychainStorage
struct LLMConfig: Codable, Equatable {
    var providerRaw: String
    var modelName: String
    var maxTokens: Int
    var localBaseURL: String
    var systemPrompt: String
    /// API 地址覆盖（非 local 提供商；空/nil = 用提供商官方默认地址）
    var baseURLOverride: String?
    /// 思考等级（off = 不下发 reasoning_effort，跟随提供商默认）
    var thinkingLevel: ThinkingLevel
    /// 上下文大小（context window token 数；nil = 跟随模型默认；仅本地提供商生效 → Ollama num_ctx）
    var contextWindow: Int?

    var provider: ModelProvider {
        get { ModelProvider(rawValue: providerRaw) ?? .deepSeek }
        set { providerRaw = newValue.rawValue }
    }

    /// 最大 Token 数合法范围（1M 量级：滑块无意义，直输 + 钳制）
    static let maxTokensRange: ClosedRange<Int> = 128 ... 1_048_576

    /// 上下文大小合法范围（1M 量级：直输 + 预设；下限 1024 = Ollama num_ctx 实用下限）
    static let contextWindowRange: ClosedRange<Int> = 1024 ... 1_048_576

    /// 生效 API 地址（local → 本地服务地址；其余 → 覆盖值优先，缺省官方地址）
    var effectiveBaseURLString: String {
        provider.effectiveBaseURL(self).absoluteString
    }

    init(providerRaw: String,
         modelName: String,
         maxTokens: Int,
         localBaseURL: String,
         systemPrompt: String,
         baseURLOverride: String?,
         thinkingLevel: ThinkingLevel,
         contextWindow: Int? = nil) {
        self.providerRaw = providerRaw
        self.modelName = modelName
        self.maxTokens = maxTokens
        self.localBaseURL = localBaseURL
        self.systemPrompt = systemPrompt
        self.baseURLOverride = baseURLOverride
        self.thinkingLevel = thinkingLevel
        self.contextWindow = contextWindow
    }

    /// 解码旧版配置（无 baseURLOverride / thinkingLevel 字段）→ 缺省值兜底
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerRaw = try c.decode(String.self, forKey: .providerRaw)
        modelName = try c.decode(String.self, forKey: .modelName)
        maxTokens = try c.decode(Int.self, forKey: .maxTokens)
        localBaseURL = try c.decode(String.self, forKey: .localBaseURL)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        baseURLOverride = try c.decodeIfPresent(String.self, forKey: .baseURLOverride)
        thinkingLevel = (try? c.decode(ThinkingLevel.self, forKey: .thinkingLevel)) ?? .off
        contextWindow = try? c.decodeIfPresent(Int.self, forKey: .contextWindow)
    }

    static let configDidChangeNotification = Notification.Name("LLMConfigDidChange")

    static func makeDefault() -> LLMConfig {
        LLMConfig(providerRaw: ModelProvider.deepSeek.rawValue,
                  modelName: "deepseek-chat",
                  maxTokens: 4096,
                  localBaseURL: "http://localhost:11434/v1",
                  systemPrompt: "你是 Harness，一个运行在 macOS 上的 AI 开发助手。回答简洁专业，代码使用代码块。",
                  baseURLOverride: nil,
                  thinkingLevel: .off)
    }

    static func load() -> LLMConfig {
        guard let data = UserDefaults.standard.data(forKey: "llmConfig"),
              let cfg = try? JSONDecoder().decode(LLMConfig.self, from: data)
        else {
            return makeDefault()
        }
        // 历史值越界钳制（旧滑块上限 8192，扩围后兼容 0/负值等脏数据）
        return Self.normalized(cfg)
    }

    /// 加载后归一化：maxTokens 钳制到合法范围；contextWindow 越界视为无效（回落跟随默认）
    static func normalized(_ cfg: LLMConfig) -> LLMConfig {
        var c = cfg
        c.maxTokens = maxTokensRange.clamp(c.maxTokens)
        if let cw = c.contextWindow, !contextWindowRange.contains(cw) {
            c.contextWindow = nil
        }
        return c
    }

    func save() {
        let c = Self.normalized(self)
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: "llmConfig")
        }
        NotificationCenter.default.post(name: LLMConfig.configDidChangeNotification, object: nil)
    }
}

enum LLMConfigStore {
    static var configDidChange: Notification.Name {
        LLMConfig.configDidChangeNotification
    }
}

extension ModelProvider {
    /// 各提供商可选模型（本地模型由用户在设置中填写）
    var selectableModels: [String] {
        switch self {
        case .openAI: ["gpt-4o", "gpt-4o-mini", "o3", "o4-mini"]
        case .deepSeek: ["deepseek-chat", "deepseek-reasoner"]
        case .anthropic: ["claude-sonnet-4-20250514", "claude-3-5-haiku-20241022"]
        case .local: []
        }
    }

    var baseURL: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1")!
        case .deepSeek: URL(string: "https://api.deepseek.com/v1")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1")!
        case .local: URL(string: "http://localhost:11434/v1")!
        }
    }
}

extension ModelProvider {
    /// 生效 API 地址：local → 本地服务地址；其他 → 覆盖值（非空）优先，缺省官方默认
    func effectiveBaseURL(_ cfg: LLMConfig) -> URL {
        if self == .local {
            return URL(string: cfg.localBaseURL) ?? URL(string: "http://localhost:11434/v1")!
        }
        let trimmed = cfg.baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let url = URL(string: trimmed) {
            return url
        }
        return baseURL
    }
}

extension ClosedRange where Bound == Int {
    func clamp(_ v: Int) -> Int {
        Swift.min(Swift.max(v, lowerBound), upperBound)
    }
}
