import Foundation
import Memory
import RAG
import Testing

/// 意义评估单元测试
@Suite("SignificanceScorer")
struct MemoryScorerTests {
    @Test func explicitMemorizeScoresHigh() {
        let s = SignificanceScorer.score("记住：项目数据库端口是 5432，配置在 /etc/app/db.conf", kind: .fact,
                                         origin: .turn)
        #expect(s >= 0.6)
    }

    @Test func shortFragmentScoresLow() {
        let s = SignificanceScorer.score("好的", kind: .fact, origin: .turn)
        #expect(s < 0.35)
    }

    @Test func decisionAndLessonMarkersBoost() {
        let base = SignificanceScorer.score("我们采用 PostgreSQL 16 作为主库，部署在 172.16.130.20", kind: .decision,
                                            origin: .turn)
        let lesson = SignificanceScorer.score("教训：备份脚本漏了 --force 参数导致静默失败，根因是版本差异",
                                              kind: .lesson, origin: .turn)
        #expect(base >= 0.4)
        #expect(lesson >= 0.4)
    }

    @Test func originFloorAndManual() {
        // manual 保底 0.6
        #expect(SignificanceScorer.score("短", kind: .fact, origin: .manual) >= 0.6)
        // feedback 保底 0.5
        #expect(SignificanceScorer.score("短", kind: .lesson, origin: .feedback) >= 0.5)
        // significanceFloor 生效
        #expect(SignificanceScorer.score("内容足够长的一段普通描述文字", kind: .context, origin: .turn,
                                         significanceFloor: 0.7) >= 0.7)
    }

    @Test func reinforcementCapsAtOne() {
        #expect(SignificanceScorer.reinforced(0.5, reinforcement: 10) == 1)
        #expect(SignificanceScorer.reinforced(0.5, reinforcement: 1) == 0.55)
    }
}

/// 一致性校验单元测试
@Suite("ConsistencyChecker")
struct MemoryConsistencyTests {
    private let checker = ConsistencyChecker()
    private let vectorizer = HashingVectorizer()

    private func item(_ content: String, topic: String = "t", status: MemoryStatus = .active) -> MemoryItem {
        MemoryItem(kind: .fact, topic: topic, content: content, significance: 0.5, status: status,
                   sourceSession: "s", origin: .turn, vector: vectorizer.embed(content))
    }

    @Test func identicalContentIsConsistent() {
        let existing = item("用户偏好深色主题的编辑器配色")
        let verdict = checker.check(content: "用户偏好深色主题的编辑器配色", topic: nil, against: [existing])
        guard case let .consistent(m) = verdict else {
            Issue.record("应判定为 consistent，实际 \(verdict)")
            return
        }
        #expect(m.id == existing.id)
    }

    @Test func negationIsConflict() {
        let existing = item("部署走 Nginx 反向代理")
        let verdict = checker.check(content: "不对，部署不走 Nginx 反向代理，直接用 Caddy", topic: nil,
                                    against: [existing])
        guard case let .conflicts(m) = verdict else {
            Issue.record("应判定为 conflicts，实际 \(verdict)")
            return
        }
        #expect(m.id == existing.id)
    }

    @Test func unrelatedContentIsUnrelated() {
        let existing = item("数据库端口 5432")
        let verdict = checker.check(content: "今天天气不错适合爬山", topic: nil, against: [existing])
        guard case .unrelated = verdict else {
            Issue.record("应判定为 unrelated，实际 \(verdict)")
            return
        }
    }

    @Test func supersededMemoryIsSkipped() {
        let existing = item("使用 Node 18", status: .superseded)
        let verdict = checker.check(content: "使用 Node 18", topic: nil, against: [existing])
        guard case .unrelated = verdict else {
            Issue.record("superseded 记忆不应参与比对，实际 \(verdict)")
            return
        }
    }

    @Test func topicMismatchSkipped() {
        let existing = item("数据库端口 5432", topic: "db")
        let verdict = checker.check(content: "数据库端口 5432", topic: "ui", against: [existing])
        guard case .unrelated = verdict else {
            Issue.record("主题不匹配不应比对，实际 \(verdict)")
            return
        }
    }

    @Test func hasContradictionMarkerDetection() {
        #expect(checker.hasContradiction("部署走 Nginx", "部署不走 Nginx"))
        #expect(!checker.hasContradiction("部署走 Nginx", "部署走 Nginx 反代"))
    }
}
