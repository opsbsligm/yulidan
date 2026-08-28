import Foundation
@testable import HarnessApp
import LLM
import XCTest

// MARK: - 配置持久化 → 真实服务端 端到端集成测试（opt-in，默认跳过）

//
// 补齐证据链的「配置持久化」半链：OllamaNativeIntegrationTests 从 LocalAdapter 直接起步，
// 本测试从 UI 保存契约起步 —— LLMConfig.save()（设置页预设按钮同款路径：归一化 + JSON → UserDefaults）
// → LLMConfig.load()（App 同源加载）→ App 同款适配器构造（AppViewModel .local 分支语义）
// → 真实 Ollama → /api/ps context_length 铁证。
// 与桩单测（wire/传播/归一化）+ OllamaNativeIntegrationTests 合并 = 上下文大小全链路证据
// （仅剩像素级点击一项，属用户清单自查项）。
//
// 运行（需本机 Ollama 已启动且已拉取测试模型）：
//   HARNESS_INTEGRATION=1 swift test --filter ConfigPersistenceIntegrationTests
// 门禁（无环境变量）：整类 XCTSkip，不依赖网络，不影响 CI。

final class ConfigPersistenceIntegrationTests: XCTestCase {
    func testContextWindowSaveLoadThenAppliedByServer() async throws {
        guard ProcessInfo.processInfo.environment["HARNESS_INTEGRATION"] != nil else {
            throw XCTSkip("未设 HARNESS_INTEGRATION（实机集成测试，需本机 Ollama）")
        }
        let env = ProcessInfo.processInfo.environment
        let model = env["OLLAMA_TEST_MODEL"] ?? "qwen3:4b"
        let numCtx = 32768
        let base = try XCTUnwrap(URL(string: "http://localhost:11434"))

        // ① 保护现场：测试进程 UserDefaults 为 xctest runner 独立域，不触碰 App 真实配置；仍保存/恢复兜底
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "llmConfig")
        defer {
            if let saved {
                defaults.set(saved, forKey: "llmConfig")
            } else {
                defaults.removeObject(forKey: "llmConfig")
            }
        }

        // ② UI 保存契约：设置页点「32K」预设的等价操作 → save()（归一化 + JSON → UserDefaults + 通知）
        var cfg = LLMConfig.makeDefault()
        cfg.provider = .local
        cfg.modelName = model
        cfg.localBaseURL = base.appendingPathComponent("v1").absoluteString
        cfg.maxTokens = 64
        cfg.contextWindow = numCtx
        cfg.save()

        // ③ App 同源加载路径（load = UserDefaults 解码 + normalized 归一化）
        let loaded = LLMConfig.load()
        XCTAssertEqual(loaded.contextWindow, numCtx, "contextWindow 持久化往返须保留（UI 保存契约铁证）")
        XCTAssertEqual(loaded.modelName, model)

        // ④ App 同款适配器构造（AppViewModel .local 分支：LocalAdapter + ProviderProfile.local(forModel:)）
        let adapter = try LocalAdapter(apiKey: "local",
                                       baseURL: XCTUnwrap(URL(string: loaded.localBaseURL)),
                                       profile: ProviderProfile.local(forModel: loaded.modelName))

        // ⑤ 真实请求：与 App 完全相同的生产路径（/api/tags 引擎探测 → 原生 /api/chat options.num_ctx）
        _ = try await adapter.request(LLMRequest(model: loaded.modelName,
                                                 messages: [Message(role: .user, content: [.text("只回复两个字：收到")])],
                                                 maxTokens: 64,
                                                 numCtx: loaded.contextWindow))

        // ⑥ ground truth：/api/ps 官方字段 context_length（= 本次请求所起 runner 的上下文）
        let found = try await pollContextLength(model: model, expected: numCtx, base: base)
        XCTAssertEqual(found, numCtx,
                       "Ollama /api/ps 须报告 context_length=\(numCtx) 的 runner（配置持久化→服务端铁证）")
    }

    /// 轮询 /api/ps 至目标模型出现 context_length==expected 的 runner（60s 超时，500ms 间隔）
    private func pollContextLength(model: String, expected: Int, base: URL) async throws -> Int? {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            var req = URLRequest(url: base.appendingPathComponent("api/ps"))
            req.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = obj["models"] as? [[String: Any]],
               let hit = models.first(where: {
                   ($0["name"] as? String) == model && ($0["context_length"] as? Int) == expected
               }) {
                return hit["context_length"] as? Int
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }
}
