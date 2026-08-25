import Foundation
import Memory
import RAG
import Session
import Testing
import Tools

/// 记忆工具 + ToolExecutor 全链路场景
@Suite("MemoryTools")
struct MemoryToolsTests {
    private let engine = MemoryEngine(store: LongTermMemoryStore())
    private var context: ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private static func text(_ r: ToolResult) -> String {
        r.content.compactMap { part in
            if case let .text(s) = part {
                return s
            }
            return nil
        }.joined(separator: "\n")
    }

    @Test func rememberThenRecallThenForget() async {
        let reg = ToolRegistry()
        for tool in MemoryTools.makeAll(engine: engine) {
            await reg.register(tool)
        }
        let executor = ToolExecutor()
        let rem = await executor.execute(ToolCall(name: "remember",
                                                  arguments: ["content": "记住：测试环境跳板机 IP 是 10.0.0.9",
                                                              "kind": "fact", "topic": "ops"]),
                                         in: reg, context: context)
        #expect(Self.text(rem).contains("已写入长期记忆"))
        let recall = await executor.execute(ToolCall(name: "recall_memory", arguments: ["query": "跳板机 IP"]),
                                            in: reg, context: context)
        #expect(Self.text(recall).contains("10.0.0.9"))
        // 从返回信息提取 id 前缀做删除
        let remText = Self.text(rem)
        let tailPart = remText.split(separator: "（").last.map(String.init) ?? ""
        let idPrefix = String(tailPart.dropLast().prefix(8))
        let forget = await executor.execute(ToolCall(name: "forget", arguments: ["id": idPrefix]),
                                            in: reg, context: context)
        #expect(Self.text(forget).contains("已删除记忆"))
        #expect(await engine.stats().active == 0)
    }

    @Test func rememberEmptyContentInvalidArgs() async throws {
        let tool = RememberTool(engine: engine)
        let r = try await tool.execute(["content": "  "], context: context)
        #expect(r.error?.code == "invalid_args")
    }

    @Test func recallEmptyQueryInvalidArgs() async throws {
        let tool = RecallMemoryTool(engine: engine)
        let r = try await tool.execute(["query": ""], context: context)
        #expect(r.error?.code == "invalid_args")
    }

    @Test func recallNoHitsMessage() async throws {
        let tool = RecallMemoryTool(engine: engine)
        let r = try await tool.execute(["query": "完全无关的罕见查询词 zzz"], context: context)
        #expect(Self.text(r).contains("没有"))
    }

    @Test func forgetMissingArgsInvalidArgs() async throws {
        let tool = ForgetTool(engine: engine)
        let r = try await tool.execute([:], context: context)
        #expect(r.error?.code == "invalid_args")
    }

    @Test func forgetUnknownIdNotFound() async throws {
        let tool = ForgetTool(engine: engine)
        let r = try await tool.execute(["id": "zzzzzzzz"], context: context)
        #expect(r.error?.code == "not_found")
    }

    @Test func makeAllReturnsThreeTools() {
        #expect(MemoryTools.makeAll(engine: engine).map(\.name).sorted()
            == ["forget", "recall_memory", "remember"])
    }
}

/// 记忆工具决策分支（merged / superseded / rejected / forget-by-topic）
@Suite("MemoryTools decision paths")
struct MemoryToolsDecisionTests {
    private let engine = MemoryEngine(store: LongTermMemoryStore())
    private var context: ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private static func text(_ r: ToolResult) -> String {
        r.content.compactMap { part in
            if case let .text(s) = part {
                return s
            }
            return nil
        }.joined(separator: "\n")
    }

    @Test("remember identical content merges into existing memory")
    func rememberMerged() async throws {
        let tool = RememberTool(engine: engine)
        let topic = "cov-merged-\(UUID().uuidString.prefix(4))"
        let content = "记住：合并探针服务的超时阈值配置为 3000 毫秒"
        let r1 = try await tool.execute(["content": content, "kind": "fact", "topic": topic],
                                        context: context)
        #expect(Self.text(r1).contains("已写入长期记忆"))
        let r2 = try await tool.execute(["content": content, "kind": "fact", "topic": topic],
                                        context: context)
        #expect(Self.text(r2).contains("已合并强化"))
    }

    @Test("remember conflicting content supersedes old memory")
    func rememberSuperseded() async throws {
        let tool = RememberTool(engine: engine)
        let topic = "cov-supersede-\(UUID().uuidString.prefix(4))"
        let r1 = try await tool.execute(
            ["content": "记住：生产数据库连接串是 jdbc:mysql://db1:3306/app", "kind": "fact", "topic": topic],
            context: context
        )
        #expect(Self.text(r1).contains("已写入长期记忆"))
        let r2 = try await tool.execute(
            ["content": "记住：生产数据库连接串不是 jdbc:mysql://db1:3306/app，已切换为 jdbc:mysql://db2:3307/app",
             "kind": "fact", "topic": topic],
            context: context
        )
        #expect(Self.text(r2).contains("取代"))
    }

    @Test("remember too-short content is rejected")
    func rememberRejected() async throws {
        let tool = RememberTool(engine: engine)
        let r = try await tool.execute(["content": "短", "kind": "fact", "topic": "cov-rej"],
                                       context: context)
        #expect(r.error?.code == "rejected")
        #expect(Self.text(r).contains("未写入"))
    }

    @Test("forget by topic removes memories; repeat reports not_found")
    func forgetByTopic() async throws {
        let rem = RememberTool(engine: engine)
        let forget = ForgetTool(engine: engine)
        let topic = "cov-topic-\(UUID().uuidString.prefix(4))"
        let r1 = try await rem.execute(["content": "主题删除探针：足够长的内容以通过意义度阈值",
                                        "kind": "fact", "topic": topic],
                                       context: context)
        #expect(Self.text(r1).contains("已写入长期记忆"))
        let f1 = try await forget.execute(["topic": topic], context: context)
        #expect(Self.text(f1).contains("已删除主题"))
        let f2 = try await forget.execute(["topic": topic], context: context)
        #expect(f2.error?.code == "not_found")
    }
}
