import Foundation
@testable import LLM
import XCTest

// MARK: - Ollama 原生路径实机集成测试（opt-in，默认跳过）

//
// 背景（2026-08-27 实机实证）：OpenAI 兼容端点不受理 options（runner 仍 -c 4096），
// 仅原生 /api/chat 的 options.num_ctx 真实生效。桩单测锁死「我方 wire」，
// 本测试锁死「服务端行为」：num_ctx → llama-server runner 的 context_length。
//
// 运行方式（需本机 Ollama 已启动且已拉取测试模型）：
//   HARNESS_INTEGRATION=1 swift test --filter OllamaNativeIntegrationTests
//   可选：OLLAMA_BASE_URL（默认 http://localhost:11434）/ OLLAMA_TEST_MODEL（默认 qwen3:4b）
// 门禁（无环境变量）：整类 XCTSkip，不依赖网络，不影响 CI。

final class OllamaNativeIntegrationTests: XCTestCase {
    /// num_ctx 端到端铁证：LocalAdapter（引擎探测→原生路径）→ Ollama → runner 以该上下文加载
    func testNumCtxActuallyAppliedByServer() async throws {
        guard ProcessInfo.processInfo.environment["HARNESS_INTEGRATION"] != nil else {
            throw XCTSkip("未设 HARNESS_INTEGRATION（实机集成测试，需本机 Ollama；桩单测已覆盖 wire 契约）")
        }
        let env = ProcessInfo.processInfo.environment
        let base = URL(string: env["OLLAMA_BASE_URL"] ?? "http://localhost:11434")!
        let model = env["OLLAMA_TEST_MODEL"] ?? "qwen3:4b"
        let numCtx = 32768

        // 走与 App 完全相同的路径：LocalAdapter 探测 /api/tags → 原生 /api/chat（options.num_ctx）
        let adapter = LocalAdapter(apiKey: "ollama", baseURL: base.appendingPathComponent("v1"), profile: .local)
        _ = try await adapter.request(LLMRequest(model: model,
                                                 messages: [Message(role: .user, content: [.text("只回复两个字：收到")])],
                                                 maxTokens: 64, numCtx: numCtx))

        // ground truth：/api/ps 报告存活 runner 的 context_length（Ollama 官方字段，2026-08-27 实证）
        // runner 按 model+options 区分：断言该模型存在 context_length==numCtx 的实例（= 本次请求所起 runner）
        var found: Int?
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            var req = URLRequest(url: base.appendingPathComponent("api/ps"))
            req.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = obj["models"] as? [[String: Any]] {
                if let hit = models.first(where: {
                    ($0["name"] as? String) == model && ($0["context_length"] as? Int) == numCtx
                }) {
                    found = hit["context_length"] as? Int
                    break
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTAssertEqual(found, numCtx,
                       "Ollama /api/ps 须报告 context_length=\(numCtx) 的 runner（num_ctx 真实生效铁证）")
    }
}
