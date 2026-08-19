import Agent
import Foundation
import LLM
import MCP
import Memory
import Prompt
import RAG
import Session
import Skill
import Subagent
import Testing
import Tools

// MARK: - 场景基建（自包含、确定性：纯内存 + 临时目录，零网络）

/// 脚本化 LLM：按序返回响应（用尽后重复最后一条，防循环越界）
private final class ScenarioScriptedLLM: LLMProvider, @unchecked Sendable {
    let id = "scenario-llm"
    let supportedModels = ["mock-model"]
    private let lock = NSLock()
    private let responses: [LLMResponse]
    private var count = 0

    init(responses: [LLMResponse]) {
        self.responses = responses
    }

    var callCount: Int {
        lock.withLock { count }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        var idx = 0
        lock.withLock {
            idx = min(count, responses.count - 1)
            count += 1
        }
        return responses[idx]
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private func scenarioText(_ text: String) -> LLMResponse {
    LLMResponse(model: "mock-model", content: [.text(text)], finishReason: .stop)
}

private func scenarioTool(_ name: String, _ arguments: String, id: String) -> LLMResponse {
    LLMResponse(model: "mock-model", content: [],
                toolCalls: [LLM.ToolCallBlock(id: id, name: name, arguments: arguments)],
                finishReason: .toolCalls)
}

/// 跨模块业务场景端到端测试
///
/// 场景叙事：用户在一个会话里提问 → 系统提示词按模型差异化渲染 → Agent 循环中
/// 依次调用「MCP 工具」与「内置文件工具」→ 会话交换蒸馏入长期记忆 → 用户反馈
/// 同时沉淀进记忆库与 RAG 知识库 → 重复任务观测产出技能候选 → 子 Agent 委派闭环。
/// 覆盖 8 大后端模块的集成链路（非单模块单点）。
@Suite("跨模块业务场景端到端")
struct CrossModuleScenarioTests {
    private static func tempDir(_ tag: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-e2e-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: 场景主链

    // MARK: 场景主链

    @Test("主链：Prompt 模型适配 → RAG 检索溯源 → AgentLoop MCP+文件工具循环")
    func promptRAGToolPipeline() async throws {
        let rendered = try await setupPrompt()
        let rag = try await setupRAG()
        let noteURL = Self.tempDir("pipeline").appendingPathComponent("note.txt")
        let registry = await setupTools(noteURL: noteURL)
        await runAgentTurn(rendered: rendered, registry: registry, noteURL: noteURL)
        await runMemoryAndFeedback(rag: rag)
        await runSubagentDelegation()
    }

    /// 段 1：Prompt 工程层（内置模板 + 模型差异化适配）
    private func setupPrompt() async throws -> RenderedPrompt {
        let store = PromptTemplateStore()
        _ = await BuiltInPromptTemplates.install(into: store)
        let engine = PromptEngine(store: store, renderer: PromptRenderer(store: store))
        let rendered = try await engine.renderDetailed(template: "agent", model: "deepseek-chat")
        #expect(rendered.text.contains("DeepSeek Harness"), "角色段缺失")
        #expect(rendered.text.contains("模型说明"), "deepseek 画像的 promptNotes 未注入（模型差异化适配失效）")
        #expect(rendered.modelFamily == "deepseek")
        // 模型差异：generic 画像无 promptNotes → 无「模型说明」段
        let generic = try await engine.renderDetailed(template: "agent", model: "unknown-model-x")
        #expect(!generic.text.contains("## 模型说明"))
        return rendered
    }

    /// 段 2：RAG（入库 → 检索 → 重排 → 过滤 → 溯源）
    private func setupRAG() async throws -> RAGEngine {
        let rag = RAGEngine(store: VectorStore())
        _ = await rag.ingestText(
            """
            Swift actor 通过串行队列隔离可变状态，防止数据竞争。\
            跨 actor 访问必须使用 await。Actor 是 Swift 并发的基础单元。
            """,
            source: "actor-guide.md", title: "Swift 并发指南", metadata: ["kind": "doc"]
        )
        let hits = await rag.retrieve(query: "actor 如何隔离状态")
        #expect(!hits.isEmpty, "RAG 检索应为空")
        #expect(hits[0].citation.contains("actor-guide.md"), "溯源引用缺失")
        #expect(hits[0].termHits > 0, "重排依据（词元命中）应为正")
        // 元数据过滤：不存在的过滤值 → 空结果
        let filtered = await rag.retrieve(query: "actor", options: .init(filter: ["kind": "nope"]))
        #expect(filtered.isEmpty, "元数据过滤失效")
        return rag
    }

    /// 段 3：MCP 工具自动注册 + 内置文件工具
    private func setupTools(noteURL: URL) async -> ToolRegistry {
        let registry = ToolRegistry()
        let mcp = MockMCPClient(name: "mock-mcp")
        await mcp.addTool(
            MCPToolSpec(name: "echo", description: "回显输入",
                        inputSchema: #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#),
            handler: { args in "echo:\(args["text"] ?? "")" }
        )
        let manager = MCPServerManager()
        await manager.register(mcp)
        let installed = await manager.installTools(into: registry)
        #expect(installed == 1, "MCP 工具应自动注册 1 个本地工具")
        #expect(await registry.names().contains("mcp_mock-mcp_echo"), "MCP 工具命名前缀缺失")
        await registry.register(WriteFileTool())
        _ = noteURL
        return registry
    }

    /// 段 4：AgentLoop 单轮 MCP + 文件工具循环
    private func runAgentTurn(rendered: RenderedPrompt, registry: ToolRegistry, noteURL: URL) async {
        let llm = ScenarioScriptedLLM(responses: [
            scenarioTool("mcp_mock-mcp_echo", #"{"text":"harness"}"#, id: "c1"),
            scenarioTool("write_file",
                         #"{"path":"\#(noteURL.path)","content":"来自工具链"}"#, id: "c2"),
            scenarioText("已完成：MCP 回显 + 文件写入 + 知识库检索"),
        ])
        let loop = AgentLoop(sessionID: SessionID(), llm: llm, tools: registry,
                             model: "mock-model", systemPrompt: rendered.text)
        await loop.send(UserMessage(content: [.text("用 MCP 回显 harness 并写入文件")]),
                        target: .nextTurn, wakeup: true)
        let result = await loop.whenIdle()
        #expect(result.error == nil, "turn 不应报错：\(result.error ?? "")")
        #expect(result.toolTraces.count == 2, "工具轨迹应为 2 条（MCP + write_file）")
        #expect(result.toolTraces.first?.name == "mcp_mock-mcp_echo")
        #expect(result.toolTraces.first?.ok == true, "MCP 工具执行应成功")
        let written = (try? String(contentsOf: noteURL, encoding: .utf8)) ?? ""
        #expect(written == "来自工具链", "write_file 落盘失败")
        let finalText = (result.steps.last?.content ?? [])
            .compactMap { block -> String? in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.joined()
        #expect(finalText.contains("已完成"), "最终回答缺失")
    }

    /// 段 5：记忆蒸馏 + 反馈双写（记忆 + RAG）
    private func runMemoryAndFeedback(rag: RAGEngine) async {
        let memory = MemoryEngine(store: LongTermMemoryStore())
        await memory.attachRAG(rag)
        let exchanges = [
            MemoryExchange(role: .user, text: "记住：actor 必须用于共享可变状态"),
            MemoryExchange(role: .assistant, text: "好的，已记住。"),
        ]
        let stored = await memory.consolidateSession(sessionID: "scenario-1", exchanges: exchanges)
        #expect(stored >= 1, "会话蒸馏应至少落 1 条记忆")
        let recalled = await memory.recall(query: "actor 共享可变状态")
        #expect(!recalled.isEmpty, "记忆召回为空")
        let outcome = await memory.applyFeedback(
            FeedbackEvent(type: .correction, sessionID: "scenario-1",
                          rawText: "不对，应该是 actor 用于隔离共享状态",
                          distilled: "用户纠正：actor 用于隔离共享状态",
                          topic: "actor")
        )
        #expect((outcome.ragChunks ?? 0) > 0, "反馈应同时沉淀进 RAG（ragChunks>0）")
        let fbHits = await rag.retrieve(query: "actor 隔离共享状态")
        #expect(fbHits.contains { $0.metadata["origin"] == "feedback" }, "RAG 中应可检索到反馈沉淀切片")
    }

    /// 段 6：子 Agent 委派（创建 → 执行 → 终态 → 槽位回收 → 销毁）
    private func runSubagentDelegation() async {
        let coord = SubagentCoordinator(maxConcurrent: 2)
        let child = AgentLoop(sessionID: SessionID(),
                              llm: ScenarioScriptedLLM(responses: [scenarioText("子任务完成")]),
                              tools: ToolRegistry(), model: "mock-model")
        let childID = await coord.spawn(agent: child,
                                        spec: SubagentSpec(name: "child", task: "执行一个简单任务"))
        let state = await coord.waitFor(childID)
        #expect(state.phase == .succeeded, "子任务应成功结束，实际 \(state.phase)")
        let counts = await coord.counts()
        #expect(counts.running == 0, "槽位应已回收")
        await coord.shutdown()
    }

    // MARK: 记忆冲突处理

    @Test("冲突信息：新事实取代旧事实（superseded 可审计）")
    func memoryConflictSupersede() async {
        let memory = MemoryEngine(store: LongTermMemoryStore())
        _ = await memory.record(MemoryCandidate(content: "部署环境是 macOS 26 稳定版", kind: .fact,
                                                topic: "环境", sourceSession: "s1", origin: .turn))
        // 用户纠正（否定信号「不是…应该是…」）→ 冲突判定：新条目取代旧条目（superseded 可审计）
        let second = await memory.record(MemoryCandidate(content: "不对，部署环境不是 macOS 26，应该是 macOS 27",
                                                         kind: .fact, topic: "环境",
                                                         sourceSession: "s2", origin: .turn))
        var supersededOK = false
        switch second {
        case let .superseded(newID, oldID):
            let store = await memory.allForLookup()
            let oldItem = store.first { $0.id == oldID }
            let newItem = store.first { $0.id == newID }
            #expect(oldItem?.status == .superseded, "旧条目应标记 superseded")
            #expect(newItem?.status == .active, "新条目应 active")
            supersededOK = true
        case .stored, .merged, .rejected:
            break
        }
        #expect(supersededOK, "同主题不同事实应触发冲突取代（superseded）")
    }

    // MARK: Skill 进化 + 版本管理

    @Test("技能进化：重复任务观测 → 自动生成候选 → 保存注册 → 版本历史")
    func skillEvolutionAndVersioning() async {
        let root = Self.tempDir("skills")
        let registry = SkillRegistry()
        let evo = SkillEvolutionEngine(registry: registry, saveRoot: root)
        // 重复观测同一任务（minRepetition 默认 2）
        for _ in 0 ..< 3 {
            await evo.observe(sessionID: "s1", task: "生成约定式提交信息并提交到本地仓库",
                              toolNames: ["exec_command"])
        }
        let candidates = await evo.evaluate()
        #expect(!candidates.isEmpty, "重复任务应产出技能候选")
        guard let candidate = candidates.first else { return }
        let saved = await registry.skill(named: candidate.name)
        #expect(saved != nil, "候选技能应已注册到 SkillRegistry")
        #expect(saved?.source.hasPrefix(root.path) == true, "技能文件应落在隔离目录")
        // 版本历史已记录（自动生成）
        let dir = SkillStore.skillDirectory(for: candidate.name, root: root)
        let history = SkillVersioning.loadHistory(directory: dir)
        #expect(!history.isEmpty, "自动生成应留版本历史")
        // 再次评估不重复生成
        let again = await evo.evaluate()
        #expect(again.isEmpty, "同名技能不应重复生成")
    }
}
