import Foundation
import RAG

// MARK: - 信息一致性校验与冲突处理

/// 一致性比对结论
public enum ConsistencyVerdict: Sendable {
    /// 与现有记忆无关联
    case unrelated
    /// 与某条现有记忆高度相似且一致 → 合并强化
    case consistent(MemoryItem)
    /// 与某条现有记忆主题相同但信息冲突 → 新取代旧
    case conflicts(MemoryItem)
}

/// 一致性校验器（向量相似 + 主题匹配 + 否定信号检测）
public struct ConsistencyChecker: Sendable {
    public var mergeThreshold: Float
    public var conflictThreshold: Float
    private let vectorizer: any TextVectorizer

    public init(mergeThreshold: Float = 0.8, conflictThreshold: Float = 0.55,
                vectorizer: any TextVectorizer = HashingVectorizer()) {
        self.mergeThreshold = mergeThreshold
        self.conflictThreshold = conflictThreshold
        self.vectorizer = vectorizer
    }

    private static let negationMarkers = ["不对", "不是", "没有", "并非", "禁用", "禁止", "别用", "不用", "不走",
                                          "不再", "停用", "弃用", "错了", "应该是", "实际上是",
                                          "never", "not ", "no longer", "wrong", "instead of"]

    /// 在现有活跃记忆中比对候选内容
    public func check(content: String, topic: String?, against existing: [MemoryItem]) -> ConsistencyVerdict {
        guard !existing.isEmpty else { return .unrelated }
        let candidateVector = vectorizer.embed(content)
        var best: (item: MemoryItem, similarity: Float)?
        for item in existing {
            guard item.status == .active else { continue }
            // 同主题优先比较；无主题时只比内容
            let sameTopic = topic.map { $0 == item.topic } ?? true
            guard sameTopic || topic == nil else { continue }
            let sim = VectorMath.cosine(candidateVector, item.vector)
            if sim > (best?.similarity ?? 0) {
                best = (item, sim)
            }
        }
        guard let best else { return .unrelated }
        if best.similarity >= mergeThreshold, !hasContradiction(content, best.item.content) {
            return .consistent(best.item)
        }
        if best.similarity >= conflictThreshold,
           hasContradiction(content, best.item.content) || sameTopicValueDiffers(content, best.item.content) {
            return .conflicts(best.item)
        }
        return .unrelated
    }

    /// 否定信号检测：一方含否定/纠正标记而另一方不含，视为信息冲突
    public func hasContradiction(_ a: String, _ b: String) -> Bool {
        let aNeg = Self.negationMarkers.contains { a.contains($0) }
        let bNeg = Self.negationMarkers.contains { b.contains($0) }
        return aNeg != bNeg
    }

    /// 同主题下核心值不同（去掉否定词后仍不相似，但主题相同）→ 值冲突
    private func sameTopicValueDiffers(_ a: String, _ b: String) -> Bool {
        let sim = VectorMath.cosine(vectorizer.embed(a), vectorizer.embed(b))
        return sim < 0.9
    }
}
