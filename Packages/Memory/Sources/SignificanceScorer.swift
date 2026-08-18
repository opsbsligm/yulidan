import Foundation

// MARK: - 记忆意义评估

/// 意义度评分（零模型启发式：显式记忆意图 > 事实密度 > 决策/教训信号 > 长度）
public enum SignificanceScorer {
    public static let memorizeMarkers = ["记住", "记一下", "以后都", "以后要", "永远", "一直用", "别再", "不要再",
                                         "偏好", "习惯是", "always", "never", "remember", "prefer"]
    public static let factMarkers = ["是", "等于", "为", "配置", "路径", "版本", "端口", "ip", "主机", "域名", "密钥名", "default", "config"]
    public static let decisionMarkers = ["决定", "采用", "改为", "改用", "切换", "选型", "最终", "decide", "switched"]
    public static let lessonMarkers = ["教训", "原因", "根因", "修复", "解决", "报错后", "因为", "导致", "avoid", "cause", "fixed"]

    /// 评估候选记忆的意义度（0…1）
    public static func score(_ content: String, kind _: MemoryKind, origin: MemoryOrigin,
                             significanceFloor: Float = 0) -> Float {
        let lower = content.lowercased()
        var s: Float = 0.25
        if memorizeMarkers.contains(where: { lower.contains($0) }) {
            s += 0.3
        }
        if factMarkers.contains(where: { lower.contains($0) }) {
            s += 0.12
        }
        if decisionMarkers.contains(where: { lower.contains($0) }) {
            s += 0.1
        }
        if lessonMarkers.contains(where: { lower.contains($0) }) {
            s += 0.1
        }
        // 信息密度：长度适中（过短多为碎片，过长未蒸馏）
        let len = content.count
        if (20 ... 400).contains(len) {
            s += 0.1
        } else if len < 8 {
            s -= 0.15
        }
        // 显式意图/反馈来源保底
        switch origin {
        case .manual:
            s = max(s, 0.6)
        case .feedback:
            s = max(s, 0.5)
        case .turn:
            break
        }
        s = max(s, significanceFloor)
        return min(1, s)
    }

    /// 强化加成：同类信息被再次确认
    public static func reinforced(_ base: Float, reinforcement: Int) -> Float {
        min(1, base + 0.05 * Float(reinforcement))
    }
}
