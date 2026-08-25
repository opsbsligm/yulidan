import Foundation
import Testing

// MARK: - Memory 包薄弱分支覆盖（覆盖审计轮 9）

// @testable：访问 internal 蒸馏静态函数（extractMemorized/extractCorrection）
@testable import Memory

@Suite("Memory Gap Coverage")
struct MemoryGapCoverageTests {
    private func makeStore() -> LongTermMemoryStore {
        LongTermMemoryStore()
    }

    /// ① record：意义度低于阈值 → rejected（reason 含「低于阈值」，区别于过短拒绝）
    @Test("record：低意义度候选（无标记词 + 过短）→ 阈值拒绝而非过短拒绝")
    func lowSignificanceThresholdRejected() async {
        let engine = MemoryEngine(store: makeStore())
        let decision = await engine.record(MemoryCandidate(
            content: "好的好的", kind: .fact, topic: "t-low", sourceSession: "s", origin: .turn
        ))
        guard case let .rejected(reason) = decision else {
            Issue.record("应 rejected，实际 \(decision)")
            return
        }
        #expect(reason.contains("低于阈值"))
        #expect(await engine.stats().active == 0)
    }

    /// ② extractMemorized：「以后都/以后要」偏好分支
    @Test("extractMemorized：以后都/以后要 → 用户偏好")
    func extractMemorizedPreference() {
        let byDuo = MemoryEngine.extractMemorized("以后都要用 pnpm 管理依赖")
        #expect(byDuo?.hasPrefix("用户偏好：") == true)
        #expect(byDuo?.contains("pnpm") == true)
        let byYao = MemoryEngine.extractMemorized("以后要跑完整回归再发布")
        #expect(byYao?.hasPrefix("用户偏好：") == true)
        // 对照：无偏好标记 → nil
        #expect(MemoryEngine.extractMemorized("今天天气不错") == nil)
    }

    /// ③ extractCorrection：「错了/不对」前缀分支（无逗号，不走 marker 分支）
    @Test("extractCorrection：错了/不对 前缀（无逗号）→ 用户纠正")
    func extractCorrectionPrefixBranch() {
        let r1 = MemoryEngine.extractCorrection("错了 部署脚本在 /opt/deploy 目录下")
        #expect(r1?.hasPrefix("用户纠正：") == true)
        #expect(r1?.contains("/opt/deploy") == true)
        let r2 = MemoryEngine.extractCorrection("不对 镜像仓库是 registry.internal:5000")
        #expect(r2?.hasPrefix("用户纠正：") == true)
        // 对照：无纠正信号 → nil
        #expect(MemoryEngine.extractCorrection("帮我写个函数") == nil)
    }

    /// ④ applyFeedback：.lesson 反馈 → 记忆种类 .lesson（feedback 来源保底意义度）
    @Test("applyFeedback：lesson 反馈 → 入库 kind=.lesson origin=.feedback")
    func feedbackLessonKind() async {
        let engine = MemoryEngine(store: makeStore())
        let outcome = await engine.applyFeedback(FeedbackEvent(
            type: .lesson, sessionID: "s-l1", rawText: "报错后修复：先清缓存再重建索引",
            distilled: "教训：重建索引前必须先清理本地缓存，否则会残留旧分片", topic: "index"
        ))
        guard case .stored = outcome.memory else {
            Issue.record("应 stored，实际 \(outcome.memory)")
            return
        }
        let all = await engine.allForLookup()
        #expect(all.contains { $0.kind == .lesson && $0.origin == .feedback })
    }

    /// ⑤ applyFeedback：.confirmation 反馈 → 记忆种类 .fact
    @Test("applyFeedback：confirmation 反馈 → 入库 kind=.fact origin=.feedback")
    func feedbackConfirmationKind() async {
        let engine = MemoryEngine(store: makeStore())
        let outcome = await engine.applyFeedback(FeedbackEvent(
            type: .confirmation, sessionID: "s-c1", rawText: "对，就是这个配置",
            distilled: "已确认：生产环境使用 Redis 集群模式，三主三从配置", topic: "redis"
        ))
        guard case .stored = outcome.memory else {
            Issue.record("应 stored，实际 \(outcome.memory)")
            return
        }
        let all = await engine.allForLookup()
        #expect(all.contains { $0.kind == .fact && $0.origin == .feedback })
    }

    /// ⑥ SharedMemoryEngine.replace：注入自定义引擎后 get 返回同一实例
    @Test("SharedMemoryEngine.replace：注入引擎后 get 返回同一实例")
    func replaceInjectsEngine() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mem-gap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shared = SharedMemoryEngine(
            fileURL: dir.appendingPathComponent("shared/longterm.json")
        )
        let injected = MemoryEngine(store: LongTermMemoryStore(
            fileURL: dir.appendingPathComponent("injected/longterm.json")
        ))
        await shared.replace(injected)
        let got = await shared.get()
        #expect(got === injected)
    }
}
