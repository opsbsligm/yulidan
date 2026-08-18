import Foundation
import Memory
import RAG
import Testing

/// MemoryEngine 端到端：评估 → 一致性 → 冲突取代 → 召回 → 总结蒸馏 → 反馈闭环
@Suite("MemoryEngine")
struct MemoryEngineTests {
    private func makeEngine(rag: RAGEngine? = nil) -> MemoryEngine {
        MemoryEngine(store: LongTermMemoryStore(), rag: rag)
    }

    // MARK: 写入与召回

    @Test func recordAndRecall() async {
        let engine = makeEngine()
        let decision = await engine.record(MemoryCandidate(
            content: "记住：生产数据库端口是 5432，配置在 /etc/app/db.conf",
            kind: .fact, topic: "db", sourceSession: "s1", origin: .turn
        ))
        guard case .stored = decision else {
            Issue.record("应 stored，实际 \(decision)")
            return
        }
        let hits = await engine.recall(query: "生产数据库端口配置")
        #expect(!hits.isEmpty)
        #expect(hits[0].topic == "db")
    }

    @Test func lowSignificanceRejected() async {
        let engine = makeEngine()
        let decision = await engine.record(MemoryCandidate(content: "嗯", kind: .fact, topic: "t",
                                                           sourceSession: "s", origin: .turn))
        guard case .rejected = decision else {
            Issue.record("过短内容应 rejected，实际 \(decision)")
            return
        }
    }

    @Test func similarContentMerges() async {
        let engine = makeEngine()
        _ = await engine.record(MemoryCandidate(content: "用户偏好深色主题的编辑器配色", kind: .preference,
                                                topic: "ui", sourceSession: "s1", origin: .turn))
        let decision = await engine.record(MemoryCandidate(content: "用户偏好深色主题的编辑器配色",
                                                           kind: .preference, topic: "ui", sourceSession: "s2",
                                                           origin: .turn))
        guard case let .merged(id) = decision else {
            Issue.record("应 merged，实际 \(decision)")
            return
        }
        #expect(await engine.stats().active == 1)
        let all = await engine.allForLookup()
        #expect(all.first(where: { $0.id == id })?.reinforcement == 2)
    }

    @Test func conflictingContentSupersedes() async {
        let engine = makeEngine()
        _ = await engine.record(MemoryCandidate(content: "决定：部署走 Nginx 反向代理，对外端口 80/443",
                                                kind: .decision, topic: "deploy", sourceSession: "s1", origin: .turn))
        let decision = await engine.record(MemoryCandidate(content: "不对，部署不走 Nginx 反向代理了，改用 Caddy 对外",
                                                           kind: .decision, topic: "deploy", sourceSession: "s2",
                                                           origin: .feedback))
        guard case .superseded = decision else {
            Issue.record("应 superseded，实际 \(decision)")
            return
        }
        // 旧记忆被标记 superseded，不再被召回
        let hits = await engine.recall(query: "部署 反向代理 Nginx Caddy")
        #expect(hits.count == 1)
        #expect(hits[0].content.contains("Caddy"))
        let old = await (engine.allForLookup()).filter { $0.status == .superseded }
        #expect(old.count == 1)
        #expect(old[0].supersededBy != nil)
    }

    @Test func promptSectionFormatted() async {
        let engine = makeEngine()
        _ = await engine.record(MemoryCandidate(content: "记住：项目 CI 用 GitHub Actions 双流水线",
                                                kind: .fact, topic: "ci", sourceSession: "s1", origin: .manual))
        let section = await engine.promptSection(query: "CI 流水线")
        #expect(section?.contains("长期记忆") == true)
        #expect(section?.contains("GitHub Actions") == true)
        // 无相关记忆 → nil
        let empty = MemoryEngine(store: LongTermMemoryStore())
        #expect(await (empty.promptSection(query: "随便什么")) == nil)
    }

    // MARK: 短期会话自动总结

    @Test func consolidateExtractsMemorizeCorrectionDecision() async {
        let engine = makeEngine()
        let exchanges: [MemoryExchange] = [
            .init(role: .user, text: "帮我看看这个报错"),
            .init(role: .assistant, text: "这是端口冲突，建议改端口。"),
            .init(role: .user, text: "记住：这台机器的 Redis 跑在 6379，密码在 vault 里"),
            .init(role: .assistant, text: "好的，已记录。"),
            .init(role: .user, text: "不对，应该是 16379 才对"),
            .init(role: .assistant, text: "明白，已更正。"),
            .init(role: .user, text: "决定采用 GRDB 做持久化层"),
        ]
        let stored = await engine.consolidateSession(sessionID: "s-1", exchanges: exchanges)
        #expect(stored >= 3) // 记住 + 纠正 + 决策 三条
        let all = await engine.allForLookup()
        #expect(all.contains(where: { $0.kind == .preference && $0.content.contains("Redis") }))
        #expect(all.contains(where: { $0.kind == .lesson && $0.content.contains("16379") }))
        #expect(all.contains(where: { $0.kind == .decision && $0.content.contains("GRDB") }))
    }

    @Test func distillIsDeterministicAndDedupes() {
        let exchanges: [MemoryExchange] = [
            .init(role: .user, text: "记住：数据库端口 5432 在 /etc/db.conf"),
            .init(role: .user, text: "记住：数据库端口 5432 在 /etc/db.conf"),
        ]
        let candidates = MemoryEngine.distill(sessionID: "s", exchanges: exchanges)
        #expect(candidates.count == 1)
    }

    // MARK: 反馈闭环（记忆库 + RAG 双更新）

    @Test func feedbackUpdatesMemoryAndRAG() async {
        let rag = RAGEngine(store: VectorStore())
        let engine = makeEngine(rag: rag)
        let outcome = await engine.applyFeedback(FeedbackEvent(
            type: .correction, sessionID: "s-9", rawText: "不对，部署脚本里镜像仓库地址写错了",
            distilled: "纠正：部署脚本的镜像仓库地址应为 registry.internal:5000，旧地址已下线",
            topic: "deploy"
        ))
        guard case .stored = outcome.memory else {
            Issue.record("反馈应写入长期记忆，实际 \(String(describing: outcome.memory))")
            return
        }
        #expect(outcome.ragChunks != nil && (outcome.ragChunks ?? 0) >= 1)
        // RAG 侧可检索到该反馈（origin=feedback 元数据）
        let hits = await rag.retrieve(query: "镜像仓库地址 registry.internal",
                                      options: .init(filter: ["origin": "feedback"]))
        #expect(!hits.isEmpty)
        #expect(hits[0].metadata["session"] == "s-9")
        // 记忆侧可召回
        let rec = await engine.recall(query: "镜像仓库地址 部署脚本")
        #expect(!rec.isEmpty)
    }

    @Test func feedbackRememberRequestBecomesPreference() async {
        let engine = makeEngine()
        _ = await engine.applyFeedback(FeedbackEvent(
            type: .rememberRequest, sessionID: "s-10", rawText: "以后都用 pnpm 代替 npm",
            distilled: "用户要求：以后都用 pnpm 代替 npm 管理依赖", topic: "toolchain"
        ))
        let all = await engine.allForLookup()
        #expect(all.contains(where: { $0.kind == .preference && $0.origin == .feedback }))
    }

    // MARK: 管理操作

    @Test func forgetByIDAndTopic() async {
        let engine = makeEngine()
        let d1 = await engine.record(MemoryCandidate(content: "记住：事实甲内容足够长", kind: .fact,
                                                     topic: "t1", sourceSession: "s", origin: .manual))
        _ = await engine.record(MemoryCandidate(content: "记住：事实乙内容足够长", kind: .fact,
                                                topic: "t2", sourceSession: "s", origin: .manual))
        guard case let .stored(id) = d1 else {
            Issue.record("应 stored")
            return
        }
        #expect(await engine.forget(id: id) == true)
        #expect(await engine.forget(topic: "t2") == 1)
        #expect(await engine.stats().active == 0)
    }

    @Test func persistenceRoundTrip() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mem-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = MemoryEngine(store: LongTermMemoryStore(fileURL: url))
        _ = await engine.record(MemoryCandidate(content: "记住：持久化验证的长期记忆内容", kind: .fact,
                                                topic: "p", sourceSession: "s", origin: .manual))
        await engine.save()

        let reloaded = MemoryEngine(store: LongTermMemoryStore(fileURL: url))
        let (active, _, _) = await reloaded.stats()
        #expect(active == 1)
        #expect(await !(reloaded.recall(query: "持久化验证 长期记忆")).isEmpty)
    }
}
