import Foundation
import RAG

// MARK: - 记忆引擎

/// 记忆引擎配置
public struct MemoryConfig: Sendable {
    /// 意义度低于该值的候选直接拒绝（不入库）
    public var significanceThreshold: Float
    /// 召回相似度最低值
    public var recallSimilarityFloor: Float
    /// 默认召回条数
    public var defaultRecallLimit: Int
    /// 提示词注入条数
    public var promptSectionLimit: Int

    public init(significanceThreshold: Float = 0.35,
                recallSimilarityFloor: Float = 0.25,
                defaultRecallLimit: Int = 5,
                promptSectionLimit: Int = 4) {
        self.significanceThreshold = significanceThreshold
        self.recallSimilarityFloor = recallSimilarityFloor
        self.defaultRecallLimit = defaultRecallLimit
        self.promptSectionLimit = promptSectionLimit
    }
}

/// 记忆引擎：短期会话总结 → 意义评估 → 一致性/冲突处理 → 长期持久记忆
///
/// 反馈闭环：对话交互反馈（纠正/显式记住/教训/确认）自动：
/// 1. 更新长期记忆库（意义度保底 + 冲突取代）；
/// 2. 蒸馏内容入库 RAG 知识库（metadata.origin = feedback），供后续检索复用。
public actor MemoryEngine {
    public let config: MemoryConfig
    private let store: LongTermMemoryStore
    private let vectorizer: any TextVectorizer
    private let checker: ConsistencyChecker
    private var rag: RAGEngine?

    public init(store: LongTermMemoryStore,
                rag: RAGEngine? = nil,
                vectorizer: any TextVectorizer = HashingVectorizer(),
                checker: ConsistencyChecker = .init(),
                config: MemoryConfig = .init()) {
        self.store = store
        self.rag = rag
        self.vectorizer = vectorizer
        self.checker = checker
        self.config = config
    }

    /// 装配 RAG（反馈沉淀入库；App/CLI 接线时注入共享引擎）
    public func attachRAG(_ engine: RAGEngine) {
        rag = engine
    }

    // MARK: 写入（评估 → 一致性 → 冲突处理）

    /// 记录一条候选记忆；返回写入决策
    public func record(_ candidate: MemoryCandidate) async -> MemoryDecision {
        let content = candidate.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 4 else {
            return .rejected(reason: "内容过短，无记忆价值")
        }
        let significance = SignificanceScorer.score(content, kind: candidate.kind,
                                                    origin: candidate.origin,
                                                    significanceFloor: candidate.significanceFloor)
        guard significance >= config.significanceThreshold else {
            return .rejected(reason: String(format: "意义度 %.2f 低于阈值 %.2f", significance,
                                            config.significanceThreshold))
        }
        let existing = await store.all(activeOnly: true)
        let verdict = checker.check(content: content, topic: candidate.topic, against: existing)
        switch verdict {
        case let .consistent(item):
            // 合并强化：保留原 id/创建时间，刷新内容与意义度
            var merged = item
            merged.content = content
            merged.updatedAt = Date()
            merged.reinforcement += 1
            merged.significance = SignificanceScorer.reinforced(max(item.significance, significance),
                                                                reinforcement: merged.reinforcement)
            merged.vector = vectorizer.embed(content)
            await store.upsert(merged)
            return .merged(existingID: item.id)
        case let .conflicts(item):
            // 新信息取代旧信息（旧条目标记 superseded，保留历史可审计）
            var old = item
            let newItemID = UUID().uuidString
            old.status = .superseded
            old.supersededBy = newItemID
            old.updatedAt = Date()
            let newItem = MemoryItem(id: newItemID, kind: candidate.kind, topic: candidate.topic,
                                     content: content, significance: max(significance, 0.5),
                                     sourceSession: candidate.sourceSession, origin: candidate.origin,
                                     vector: vectorizer.embed(content))
            await store.upsert(old)
            await store.upsert(newItem)
            return .superseded(newID: newItem.id, oldID: item.id)
        case .unrelated:
            let item = MemoryItem(kind: candidate.kind, topic: candidate.topic, content: content,
                                  significance: significance, sourceSession: candidate.sourceSession,
                                  origin: candidate.origin, vector: vectorizer.embed(content))
            await store.upsert(item)
            return .stored(id: item.id)
        }
    }

    // MARK: 召回

    /// 召回相关记忆（仅 active；score = 0.7×余弦 + 0.3×意义度）
    public func recall(query: String, limit: Int? = nil) async -> [MemoryItem] {
        let queryVector = vectorizer.embed(query)
        let items = await store.all(activeOnly: true)
        let scored: [(item: MemoryItem, score: Float)] = items.compactMap { item in
            let cos = VectorMath.cosine(queryVector, item.vector)
            guard cos >= config.recallSimilarityFloor else { return nil }
            let score = min(1, 0.7 * cos + 0.3 * item.significance)
            return (item, score)
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit ?? config.defaultRecallLimit)
            .map(\.item))
    }

    /// 提示词注入段（渲染进系统提示词 {{#context}} 块；无相关记忆返回 nil）
    public func promptSection(query: String? = nil, limit: Int? = nil) async -> String? {
        let items: [MemoryItem] = if let query {
            await recall(query: query, limit: limit)
        } else {
            await Array((store.all(activeOnly: true)).prefix(limit ?? config.promptSectionLimit))
        }
        guard !items.isEmpty else { return nil }
        var lines = ["【长期记忆（与当前任务相关的已确认信息，可直接引用；如与用户最新指令冲突，以用户指令为准）】"]
        for item in items {
            let topic = item.topic.isEmpty ? "-" : item.topic
            lines.append("· [\(item.kind.rawValue)/\(topic)] \(item.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 短期会话 → 长期记忆（自动总结蒸馏）

    /// 对一轮会话交换做启发式蒸馏：显式记住 / 纠正 / 决策 / 关键事实 → 候选记忆
    /// 返回入库（stored/superseded）条数
    @discardableResult
    public func consolidateSession(sessionID: String, exchanges: [MemoryExchange]) async -> Int {
        var stored = 0
        for candidate in Self.distill(sessionID: sessionID, exchanges: exchanges) {
            let decision = await record(candidate)
            if case .stored = decision {
                stored += 1
            }
            if case .superseded = decision {
                stored += 1
            }
        }
        return stored
    }

    /// 启发式蒸馏规则（零模型；与 RAG 重排同一设计哲学：可解释、无模型依赖）
    public static func distill(sessionID: String, exchanges: [MemoryExchange]) -> [MemoryCandidate] {
        var candidates: [MemoryCandidate] = []
        for exchange in exchanges {
            guard exchange.role == .user else { continue }
            let text = exchange.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 8 else { continue }
            // 1) 显式记住：「记住 X / 记一下 X / 以后都 X / 偏好 X」
            if let memorized = extractMemorized(text) {
                let kind: MemoryKind = SignificanceScorer.decisionMarkers.contains { text.contains($0) }
                    ? .decision : .preference
                candidates.append(MemoryCandidate(content: memorized, kind: kind, topic: topic(of: memorized),
                                                  sourceSession: sessionID, origin: .turn,
                                                  significanceFloor: 0.6))
                continue
            }
            // 2) 纠正：「不对/错了/应该是 X / 实际上是 X」→ 教训
            if let correction = extractCorrection(text) {
                candidates.append(MemoryCandidate(content: correction, kind: .lesson, topic: topic(of: correction),
                                                  sourceSession: sessionID, origin: .turn,
                                                  significanceFloor: 0.5))
                continue
            }
            // 3) 决策：「决定/采用/改为/切换 X」
            if let decision = extractDecision(text) {
                candidates.append(MemoryCandidate(content: decision, kind: .decision, topic: topic(of: decision),
                                                  sourceSession: sessionID, origin: .turn,
                                                  significanceFloor: 0.45))
            }
        }
        // 去重（同内容只留一条）
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.content).inserted }
    }

    static func extractMemorized(_ text: String) -> String? {
        for marker in ["记住", "记一下", "remember that", "remember"] {
            if let range = text.range(of: marker) {
                let tail = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if tail.count >= 6 {
                    return "用户要求记住：\(trimSentence(tail))"
                }
            }
        }
        if text.contains("以后都") || text.contains("以后要") {
            return "用户偏好：\(trimSentence(text))"
        }
        return nil
    }

    static func extractCorrection(_ text: String) -> String? {
        for marker in ["应该是", "实际上是", "不对，", "错了，", "actually it", "should be"] {
            if let range = text.range(of: marker) {
                let tail = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if tail.count >= 4 {
                    return "用户纠正：\(trimSentence(tail))"
                }
            }
        }
        for prefix in ["不对", "错了"] where text.hasPrefix(prefix) {
            let tail = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.count >= 6 {
                return "用户纠正：\(trimSentence(tail))"
            }
        }
        return nil
    }

    static func extractDecision(_ text: String) -> String? {
        for marker in ["决定采用", "决定用", "决定", "采用", "改为", "改用", "切换为", "切换到"] {
            if let range = text.range(of: marker) {
                let tail = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if tail.count >= 4 {
                    return "已确认决策：\(trimSentence(tail))"
                }
            }
        }
        return nil
    }

    static func trimSentence(_ s: String) -> String {
        let cut = s.range(of: "[。！!？?]\\s*$")
        let body = cut.map { String(s[s.startIndex ..< $0.lowerBound]) } ?? s
        return String(body.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func topic(of content: String) -> String {
        // 取前 12 字符做主题键（同主题聚类比对用；足够稳定即可，无需精确）
        String(content.prefix(12))
    }

    // MARK: 反馈闭环（交互反馈 → 记忆库 + RAG 知识库迭代更新）

    /// 处理一条对话交互反馈：
    /// 1. 长期记忆库：按反馈类型映射记忆种类写入（意义度保底，冲突自动取代）；
    /// 2. RAG 知识库：蒸馏内容入库（origin=feedback 元数据），供 Agent 后续检索。
    public func applyFeedback(_ event: FeedbackEvent) async -> FeedbackOutcome {
        let kind: MemoryKind = switch event.type {
        case .correction:
            .lesson
        case .rememberRequest:
            .preference
        case .lesson:
            .lesson
        case .confirmation:
            .fact
        }
        let candidate = MemoryCandidate(
            content: event.distilled.count >= 4 ? event.distilled : "用户反馈（\(event.type.rawValue)）：\(event.rawText.prefix(120))",
            kind: kind, topic: event.topic, sourceSession: event.sessionID, origin: .feedback,
            significanceFloor: 0.5
        )
        let decision = await record(candidate)

        var ragChunks: Int?
        if let rag {
            let chunks = await rag.ingestText(event.distilled, source: "feedback:\(event.sessionID)",
                                              title: "对话沉淀-\(event.type.rawValue)",
                                              metadata: ["origin": "feedback", "session": event.sessionID,
                                                         "kind": kind.rawValue])
            ragChunks = chunks
        }
        return FeedbackOutcome(memory: decision, ragChunks: ragChunks)
    }

    // MARK: 管理

    /// 全部记忆（含非活跃；forget 前缀查找用）
    public func allForLookup() async -> [MemoryItem] {
        await store.all(activeOnly: false)
    }

    public func forget(id: String) async -> Bool {
        await store.remove(id)
    }

    public func forget(topic: String) async -> Int {
        let items = await (store.byTopic(topic)).filter { $0.status == .active }
        for item in items {
            _ = await store.remove(item.id)
        }
        return items.count
    }

    public func stats() async -> (active: Int, total: Int, revision: Int) {
        await (store.count(activeOnly: true), store.count(activeOnly: false), store.revision)
    }

    public func save() async {
        await store.save()
    }
}

// MARK: - 进程级共享实例

/// 进程级共享记忆引擎（默认库：~/.harness/memory/longterm.json）
public actor SharedMemoryEngine {
    public static let shared = SharedMemoryEngine()

    private var engine: MemoryEngine?

    /// 当前长期记忆路径（契约 v2：工作区根切换时经 resetFileURL 重路由，双根严格隔离不迁移）
    private var fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? LongTermMemoryStore.defaultFileURL
    }

    /// 契约 v2：工作区根切换（本地 ⇄ iCloud）后重路由长期记忆路径；
    /// 丢弃既有引擎实例，下次 get() 在新路径上重建（严格隔离，不自动迁移数据）
    public func resetFileURL(_ url: URL) {
        fileURL = url
        engine = nil
    }

    public func get() -> MemoryEngine {
        if let engine {
            return engine
        }
        let engine = MemoryEngine(store: LongTermMemoryStore(fileURL: fileURL))
        self.engine = engine
        return engine
    }

    /// 测试用：注入自定义引擎
    public func replace(_ engine: MemoryEngine) {
        self.engine = engine
    }
}
