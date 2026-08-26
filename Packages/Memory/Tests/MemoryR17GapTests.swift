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
    /// 生产代码奇特性（轮 17 实锤，记 P2）：range(of:) 缺 .regularExpression 选项 → 按字面查找，
    /// 尾部标点剥离实际失效；当前行为下仅「字面含模式文本」的输入能触发 map 闭包。
    @Test("trimSentence: 模式文本字面匹配 → map 闭包")
    func trimSentencePatternLiteral() {
        let prefix = String(repeating: "覆盖", count: 40)
        let input = prefix + "[。！!？?]" + String("\\s*$")
        let out = MemoryEngine.trimSentence(input)
        #expect(out == prefix)
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
