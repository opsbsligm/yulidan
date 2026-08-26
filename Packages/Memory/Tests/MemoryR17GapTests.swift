import Foundation
@testable import Memory
import RAG
import Session
import Testing
import Tools

// MARK: - 覆盖审计轮 17：Memory 残余兜底行（工具参数兜底 / consolidateSession stored 分支 / trimSentence / 存储排序闭包）

@Suite("Memory R17 Gap Coverage")
struct MemoryR17GapTests {
    private let vectorizer = HashingVectorizer()

    private func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private func item(_ id: String, sig: Float, topic: String, content: String) -> MemoryItem {
        MemoryItem(id: id, kind: .fact, topic: topic, content: content,
                   significance: sig, sourceSession: "s-r17", origin: .manual,
                   vector: vectorizer.embed(content))
    }

    // MARK: RememberTool 参数兜底

    /// ① 缺 content → `?? ""` 兜底 → 空内容拒绝
    @Test("RememberTool: 缺 content → 兜底 + 拒绝")
    func rememberMissingContent() async throws {
        let tool = RememberTool(engine: MemoryEngine(store: LongTermMemoryStore()))
        let result = try await tool.execute([:], context: context())
        #expect(result.error?.code == "invalid_args")
    }

    /// ② kind 缺省 `?? "fact"` + topic 缺省 `?? ""` 兜底命中；内容过短 → rejected
    @Test("RememberTool: kind/topic 兜底 + 短内容拒绝")
    func rememberShortContent() async throws {
        let tool = RememberTool(engine: MemoryEngine(store: LongTermMemoryStore()))
        let result = try await tool.execute(["content": "x"], context: context())
        #expect(result.error?.code == "rejected")
    }

    /// ③ 非法 kind rawValue → `?? .fact` 兜底（manual 来源意义度保底 0.6 → 必入库）
    @Test("RememberTool: 非法 kind → .fact 兜底入库")
    func rememberBogusKind() async throws {
        let store = LongTermMemoryStore()
        let tool = RememberTool(engine: MemoryEngine(store: store))
        let result = try await tool.execute(
            ["content": "用户偏好使用中文回复所有技术问题", "kind": "bogus"], context: context()
        )
        #expect(result.error == nil)
        let stored = await store.all()
        #expect(stored.count == 1)
        #expect(stored.first?.kind == .fact)
    }

    // MARK: RecallMemoryTool 参数兜底

    /// ④ 缺 query → `?? ""` 兜底 → 拒绝
    @Test("RecallMemoryTool: 缺 query → 兜底 + 拒绝")
    func recallToolMissingQuery() async throws {
        let tool = RecallMemoryTool(engine: MemoryEngine(store: LongTermMemoryStore()))
        let result = try await tool.execute([:], context: context())
        #expect(result.error?.code == "invalid_args")
    }

    // MARK: MemoryEngine 召回与蒸馏

    /// ⑤ 两条同文本不同意义度 → 余弦均为 1 → 排序闭包执行，高意义度在前
    @Test("recall: 同向量不同意义度 → 排序闭包")
    func recallSortClosure() async {
        let store = LongTermMemoryStore()
        let text = "部署环境是 Proxmox VE 集群"
        await store.upsert(item("m-low", sig: 0.5, topic: "env-1", content: text))
        await store.upsert(item("m-high", sig: 0.8, topic: "env-2", content: text))
        let engine = MemoryEngine(store: store)
        let items = await engine.recall(query: text)
        #expect(items.count == 2)
        #expect(items.first?.id == "m-high")
    }

    /// ⑥ 显式「记住 X」→ 蒸馏 → .stored 分支（stored += 1 两行）
    @Test("consolidateSession: 显式记住 → stored 计数分支")
    func consolidateExplicitRemember() async {
        let engine = MemoryEngine(store: LongTermMemoryStore())
        let stored = await engine.consolidateSession(
            sessionID: "s-r17",
            exchanges: [MemoryExchange(role: .user, text: "记住 我的部署环境是 Proxmox VE 集群")]
        )
        #expect(stored == 1)
    }

    /// ⑦ trimSentence → map 闭包分支
    /// 轮 18 修复回归：range(of:) 补 .regularExpression 后尾部标点剥离真实生效（轮 17 定性 P2 已修）。
    @Test("trimSentence: 尾部标点正则剥离（轮 18 修复回归）")
    func trimSentencePatternLiteral() {
        // 尾部单标点剥离
        #expect(MemoryEngine.trimSentence("记住要用 pnpm 管理依赖。") == "记住要用 pnpm 管理依赖")
        // 多个尾部标点 + 尾部空白全部剥离
        #expect(MemoryEngine.trimSentence("部署完成！ \n") == "部署完成")
        // 句中句号（非尾部）不剥离
        #expect(MemoryEngine.trimSentence("句中句号。结尾无标点") == "句中句号。结尾无标点")
        // 修复前行为回归：字面模式文本不再触发字面匹配（输入以 $ 结尾，正则不匹配 → 原文保留）
        let prefix = String(repeating: "覆盖", count: 40)
        let input = prefix + "[。！!？?]" + String("\\s*$")
        #expect(MemoryEngine.trimSentence(input) == String(input.prefix(200)))
        // 长输入 → prefix(200)
        let long = String(repeating: "甲", count: 250) + "。"
        #expect(MemoryEngine.trimSentence(long).count == 200)
    }

    // MARK: LongTermMemoryStore 排序闭包

    /// ⑧ all() 不同意义度 → 排序闭包执行（高意义度在前）
    @Test("store.all: 不同意义度 → 排序闭包")
    func allSortClosure() async {
        let store = LongTermMemoryStore()
        await store.upsert(item("low", sig: 0.3, topic: "t1", content: "第一条测试记忆内容"))
        await store.upsert(item("high", sig: 0.9, topic: "t2", content: "第二条测试记忆内容"))
        let list = await store.all()
        #expect(list.first?.id == "high")
    }

    /// ⑨ byTopic 同主题两条不同 updatedAt → 排序闭包执行（新在前）
    @Test("store.byTopic: 同主题 updatedAt 排序闭包")
    func byTopicSortClosure() async {
        let store = LongTermMemoryStore()
        let a = item("old", sig: 0.5, topic: "same-topic", content: "旧记忆条目")
        await store.upsert(a)
        var b = item("new", sig: 0.5, topic: "same-topic", content: "新记忆条目")
        b.updatedAt = a.updatedAt.addingTimeInterval(1)
        await store.upsert(b)
        let list = await store.byTopic("same-topic")
        #expect(list.first?.id == "new")
    }
}
