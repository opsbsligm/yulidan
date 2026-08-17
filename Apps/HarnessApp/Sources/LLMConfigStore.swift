import Foundation

/// 非敏感 LLM 配置（提供商/模型/参数）— UserDefaults 存储
/// 敏感的 API Key 仍走 KeychainStorage
struct LLMConfig: Codable, Equatable {
    var providerRaw: String
    var modelName: String
    var maxTokens: Int
    var localBaseURL: String
    var systemPrompt: String

    var provider: ModelProvider {
        get { ModelProvider(rawValue: providerRaw) ?? .deepSeek }
        set { providerRaw = newValue.rawValue }
    }

    static let configDidChangeNotification = Notification.Name("LLMConfigDidChange")

    static func makeDefault() -> LLMConfig {
        LLMConfig(providerRaw: ModelProvider.deepSeek.rawValue,
                  modelName: "deepseek-chat",
                  maxTokens: 4096,
                  localBaseURL: "http://localhost:11434/v1",
                  systemPrompt: "你是 Harness，一个运行在 macOS 上的 AI 开发助手。回答简洁专业，代码使用代码块。")
    }

    static func load() -> LLMConfig {
        guard let data = UserDefaults.standard.data(forKey: "llmConfig"),
              let cfg = try? JSONDecoder().decode(LLMConfig.self, from: data)
        else {
            return makeDefault()
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
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
