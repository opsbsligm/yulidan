import Foundation
@testable import HarnessApp
import LLM
import Testing

// MARK: - P0.1.5 会话工作区全链路 e2e（AppViewModel → AgentLoop → 工具执行 → 文件落盘）

// 从 WorkspaceRoutingTests 拆出（SwiftLint file_length ≤ 600）；夹具复用 AppWorkspaceFixture

@MainActor
@Suite("会话工作区全链路 e2e", .serialized)
struct WorkspaceRoutingE2ETests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    @Test("全链路：会话内 Agent 相对路径写入落会话工作区 agents/<sessionID>")
    func agentTurnWritesIntoSessionWorkspace() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        let provider = WsScriptedProvider()
        vm.providerFactoryOverride = { _, _ in provider }
        vm.llmConfig.provider = .local
        vm.createNewSession(silent: true)
        guard let session = vm.sessions.first else {
            Issue.record("未创建会话")
            return
        }
        // 等内置工具（write_file）注册完成
        let regDeadline = Date().addingTimeInterval(10)
        while Date() < regDeadline, !vm.tools.contains(where: { $0.name == "write_file" }) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.tools.contains { $0.name == "write_file" }, "内置工具未注册")
        vm.sendMessage("把产物写入会话工作区")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, vm.isGenerating {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.isGenerating == false, "生成应收敛")
        let expected = fx.localRoot.appendingPathComponent(
            "agents/\(session.id.rawValue.uuidString)/artifact.txt"
        )
        #expect(FileManager.default.fileExists(atPath: expected.path),
                "文件应落会话工作区 agents/<sessionID>：\(expected.path)")
        #expect((try? String(contentsOf: expected, encoding: .utf8)) == "ws-e2e")
    }
}

/// 脚本化供应商：第一轮 write_file（相对路径），第二轮收尾
private final class WsScriptedProvider: LLMProvider, @unchecked Sendable {
    let id = "ws-llm"
    let supportedModels = ["mock-model"]
    private let lock = NSLock()
    private var count = 0

    func request(_: LLMRequest) async throws -> LLMResponse {
        let n = lock.withLock {
            count += 1
            return min(count, 2)
        }
        if n == 1 {
            return LLMResponse(model: "mock-model", content: [],
                               toolCalls: [LLM.ToolCallBlock(id: "c1", name: "write_file",
                                                             arguments: #"{"path":"artifact.txt","content":"ws-e2e"}"#)],
                               finishReason: .toolCalls)
        }
        return LLMResponse(model: "mock-model", content: [.text("done")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
