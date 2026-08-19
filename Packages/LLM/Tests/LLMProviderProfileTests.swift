import Foundation
import LLM
import Testing

// MARK: - 本地画像按模型名细分（P2）

@Suite("ProviderProfile.local(forModel:) 模型细分")
struct LocalProfileModelTests {
    @Test("已知工具模型族开启工具调用")
    func toolCapableFamilies() {
        for model in ["qwen3-8b", "Qwen2.5-Coder-7B-Instruct", "llama3.1:8b",
                      "llama-3.2-3b", "gemma3:4b", "gemma-3-270m", "mistral-small3.1",
                      "gpt-oss-20b", "deepseek-v3:8b", "minimax-m2:8b"] {
            #expect(ProviderProfile.local(forModel: model).supportsToolCalls, "\(model)")
        }
    }

    @Test("未知/旧模型保守关闭")
    func conservativeDefault() {
        for model in ["llama3:8b", "gemma2:9b", "tiny-random-model", "phi-3-mini"] {
            #expect(!ProviderProfile.local(forModel: model).supportsToolCalls, "\(model)")
        }
    }

    @Test("deepseek-r1 同时开启 reasoning")
    func r1Reasoning() {
        let r1 = ProviderProfile.local(forModel: "deepseek-r1:7b")
        #expect(r1.supportsToolCalls)
        #expect(r1.supportsReasoning)
        let v3 = ProviderProfile.local(forModel: "deepseek-v3:8b")
        #expect(v3.supportsToolCalls)
        #expect(!v3.supportsReasoning)
    }

    @Test("大小写不敏感")
    func caseInsensitive() {
        #expect(ProviderProfile.local(forModel: "QWEN3-32B").supportsToolCalls)
        #expect(!ProviderProfile.local(forModel: "UNKNOWN").supportsToolCalls)
    }
}
