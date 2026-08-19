import Foundation
@testable import HarnessApp
import LLM
import Session
import Skill
import Testing
import Tools

// MARK: - AppViewModel 主聊天 AgentLoop 工具循环（E2E：脚本化 LLM + 真实工具注册表/执行器）

@MainActor
@Suite("AppViewModel 主聊天工具循环", .serialized)
struct AppViewModelToolLoopTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
        AppViewModel.providerFactory = nil
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-toolloop-test-\(UUID().uuidString).sqlite")
    }

    @Test("sendMessage 驱动完整工具循环：下发 tools → 执行 → 结果回填 → 收敛")
    func toolLoopE2E() async {
        let provider = ScriptedToolLoopProvider()
        AppViewModel.providerFactory = { _, _ in provider }
        defer { AppViewModel.providerFactory = nil }

        let dbURL = tempDBURL()
        AppViewModel.sessionDBURLOverride = dbURL
        defer {
            AppViewModel.sessionDBURLOverride = nil
            try? FileManager.default.removeItem(at: dbURL)
        }

        let skillDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-toolloop-skills-\(UUID().uuidString)")
        SkillStore.userSkillsDirectoryOverride = skillDir
        defer { SkillStore.userSkillsDirectoryOverride = nil }

        let vm = AppViewModel(skillUserDirectory: skillDir)
        vm.llmConfig.provider = .local // hasAPIKey = true，走测试缝 provider
        let tool = EchoTool()
        await vm.toolRegistry.register(tool)

        vm.sendMessage("请回显 hello")

        // 轮询等待生成收敛（AgentLoop 后台 Task 异步执行）
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !vm.isGenerating,
               let last = vm.messages.last, last.role == .assistant, last.status == .delivered,
               !last.content.isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(vm.isGenerating == false)
        // 工具循环走了两轮：第一轮 tool_calls，第二轮最终回答
        #expect(provider.requestCount == 2)
        // 工具真实执行了一次
        #expect(tool.executionCount == 1)
        // 第一轮请求下发了工具 schema
        if let req1 = provider.requests.first {
            #expect(req1.tools?.contains(where: { $0.name == "echo_tool" }) == true)
        }
        // 第二轮请求体含 tool 结果回填
        let hasToolResult = provider.requests.count > 1
            && provider.requests[1].messages.contains(where: { $0.role == .tool })
        #expect(hasToolResult)
        // 会话消息流：用户 → 工具轨迹 → 助手最终回答
        #expect(vm.messages.map(\.role).contains(.tool))
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.content == "done: hello")
    }

    @Test("无工具响应时单轮收敛（与旧行为兼容）")
    func plainTextOnly() async {
        let provider = PlainTextProvider()
        AppViewModel.providerFactory = { _, _ in provider }
        defer { AppViewModel.providerFactory = nil }

        let dbURL = tempDBURL()
        AppViewModel.sessionDBURLOverride = dbURL
        defer {
            AppViewModel.sessionDBURLOverride = nil
            try? FileManager.default.removeItem(at: dbURL)
        }

        let skillDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-toolloop-skills-\(UUID().uuidString)")
        SkillStore.userSkillsDirectoryOverride = skillDir
        defer { SkillStore.userSkillsDirectoryOverride = nil }

        let vm = AppViewModel(skillUserDirectory: skillDir)
        vm.llmConfig.provider = .local

        vm.sendMessage("你好")

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !vm.isGenerating,
               let last = vm.messages.last, last.role == .assistant, last.status == .delivered,
               !last.content.isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(vm.isGenerating == false)
        #expect(provider.requestCount == 1)
        #expect(vm.messages.last?.content == "你好！")
        #expect(!vm.messages.map(\.role).contains(.tool))
    }
}

// MARK: - 测试桩

/// 脚本化 LLM：第一轮返回工具调用，第二轮返回最终回答
private final class ScriptedToolLoopProvider: LLMProvider, @unchecked Sendable {
    let id = "scripted-tool-loop"
    let supportedModels = ["test-model"]
    private let lock = NSLock()
    private var count = 0
    private var recorded: [LLMRequest] = []

    var requestCount: Int {
        lock.withLock { count }
    }

    var requests: [LLMRequest] {
        lock.withLock { recorded }
    }

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        var n = 0
        lock.withLock {
            count += 1
            n = count
            recorded.append(request)
        }
        if n == 1 {
            return LLMResponse(
                model: "test-model",
                content: [.text("我来回显。")],
                toolCalls: [LLM.ToolCallBlock(id: "call-test-1", name: "echo_tool", arguments: #"{"text":"hello"}"#)],
                finishReason: .toolCalls
            )
        }
        return LLMResponse(model: "test-model", content: [.text("done: hello")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// 纯文本 LLM（无工具调用）
private final class PlainTextProvider: LLMProvider, @unchecked Sendable {
    let id = "plain-text"
    let supportedModels = ["test-model"]
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.withLock { count }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        lock.withLock { count += 1 }
        return LLMResponse(model: "test-model", content: [.text("你好！")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// 记录执行次数的回显工具
private final class EchoTool: Tool, @unchecked Sendable {
    let name = "echo_tool"
    let description = "回显文本（测试用）"
    let parameterSchema = #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#
    private let lock = NSLock()
    private var executions = 0

    var executionCount: Int {
        lock.withLock { executions }
    }

    func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        lock.withLock { executions += 1 }
        return ToolResult(content: [.text("echo: \(args["text"] ?? "")")])
    }
}
