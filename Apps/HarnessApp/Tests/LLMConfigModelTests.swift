import Foundation
@testable import HarnessApp
import LLM
import Testing

// MARK: - LLMConfig 扩展字段（API 地址覆盖 / 思考等级 / maxTokens 扩围）不变量

@Suite("LLMConfig 模型")
struct LLMConfigModelTests {
    /// 旧版 plist 转储（无 baseURLOverride / thinkingLevel 字段）
    private let legacyJSON = """
    {"providerRaw":"local","systemPrompt":"x","modelName":"qwen3:4b","maxTokens":4096,"localBaseURL":"http://localhost:11434/v1"}
    """

    @Test("旧版配置解码：新字段取缺省值")
    func legacyConfigDecodes() throws {
        let cfg = try JSONDecoder().decode(LLMConfig.self, from: Data(legacyJSON.utf8))
        #expect(cfg.provider == .local)
        #expect(cfg.baseURLOverride == nil)
        #expect(cfg.thinkingLevel == .off)
        #expect(cfg.maxTokens == 4096)
    }

    @Test("maxTokens 钳制：越界归一化到 128–1M")
    func maxTokensClamp() {
        var cfg = LLMConfig.makeDefault()
        cfg.maxTokens = 10_000_000
        #expect(LLMConfig.normalized(cfg).maxTokens == 1_048_576)
        cfg.maxTokens = 1
        #expect(LLMConfig.normalized(cfg).maxTokens == 128)
        cfg.maxTokens = 262_144
        #expect(LLMConfig.normalized(cfg).maxTokens == 262_144)
    }

    @Test("生效地址：local 恒用本地服务地址")
    func localBaseURLWins() {
        var cfg = LLMConfig.makeDefault()
        cfg.provider = .local
        cfg.localBaseURL = "http://192.168.1.9:11434/v1"
        cfg.baseURLOverride = "https://should-be-ignored.example/v1"
        #expect(cfg.effectiveBaseURLString == "http://192.168.1.9:11434/v1")
    }

    @Test("生效地址：覆盖值优先于官方默认")
    func overrideWinsOverDefault() {
        var cfg = LLMConfig.makeDefault()
        cfg.provider = .deepSeek
        cfg.baseURLOverride = "https://proxy.example.com/v1"
        #expect(cfg.effectiveBaseURLString == "https://proxy.example.com/v1")

        cfg.baseURLOverride = "   "
        #expect(cfg.effectiveBaseURLString == "https://api.deepseek.com/v1")

        cfg.baseURLOverride = nil
        #expect(cfg.effectiveBaseURLString == "https://api.deepseek.com/v1")
    }

    @Test("编码往返：新字段保真")
    func roundTrip() throws {
        var cfg = LLMConfig.makeDefault()
        cfg.provider = .openAI
        cfg.baseURLOverride = "https://relay.example.com/v1"
        cfg.thinkingLevel = .high
        cfg.maxTokens = 1_048_576
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(LLMConfig.self, from: data)
        #expect(back == cfg)
    }
}
