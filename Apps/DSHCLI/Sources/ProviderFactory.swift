import LLM

/// 与 GUI AppViewModel.makeProvider 一致的适配器工厂
enum ProviderFactory {
    static func make(_ cfg: DSHConfig.Resolved) -> any LLMProvider {
        switch cfg.provider {
        case "openai":
            OpenAIAdapter(apiKey: cfg.apiKey, baseURL: cfg.baseURL)
        case "anthropic":
            AnthropicAdapter(apiKey: cfg.apiKey, baseURL: cfg.baseURL)
        case "local":
            LocalAdapter(apiKey: cfg.apiKey.isEmpty ? "local" : cfg.apiKey,
                         baseURL: cfg.baseURL,
                         profile: ProviderProfile.local(forModel: cfg.model))
        default:
            DeepSeekAdapter(apiKey: cfg.apiKey, baseURL: cfg.baseURL)
        }
    }
}
