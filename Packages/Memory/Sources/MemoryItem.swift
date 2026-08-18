import Foundation

// MARK: - 记忆系统核心类型

/// 记忆种类
public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    /// 事实（配置/路径/版本/环境信息）
    case fact
    /// 用户偏好（习惯/风格/口味）
    case preference
    /// 决策（已确认的方案取舍）
    case decision
    /// 经验教训（踩坑/修复过程/根因）
    case lesson
    /// 背景上下文（长期项目状态）
    case context
}

/// 记忆状态
public enum MemoryStatus: String, Codable, Sendable {
    /// 生效中
    case active
    /// 被新信息取代（保留历史，不参与召回）
    case superseded
    /// 用户主动归档
    case archived
}

/// 记忆来源
public enum MemoryOrigin: String, Codable, Sendable {
    /// 对话自动总结
    case turn
    /// 交互反馈沉淀（纠正/确认/教训/显式记住）
    case feedback
    /// 用户或 Agent 显式 remember
    case manual
}

/// 长期记忆条目
public struct MemoryItem: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public var kind: MemoryKind
    /// 主题键（同主题新信息优先做一致性比对）
    public var topic: String
    /// 记忆正文（精炼后的一句话/一段话）
    public var content: String
    /// 意义度 0…1（召回加权 + 衰减依据）
    public var significance: Float
    public var status: MemoryStatus
    public var createdAt: Date
    public var updatedAt: Date
    /// 来源会话
    public var sourceSession: String
    public var origin: MemoryOrigin
    /// 同类信息被再次确认的次数（强化计数）
    public var reinforcement: Int
    /// 取代本条的新记忆 id
    public var supersededBy: String?
    /// 向量（HashingVectorizer，召回用）
    public var vector: [Float]

    public init(id: String = UUID().uuidString,
                kind: MemoryKind, topic: String, content: String,
                significance: Float, status: MemoryStatus = .active,
                sourceSession: String, origin: MemoryOrigin,
                reinforcement: Int = 1, supersededBy: String? = nil,
                vector: [Float] = []) {
        self.id = id
        self.kind = kind
        self.topic = topic
        self.content = content
        self.significance = min(1, max(0, significance))
        self.status = status
        let now = Date()
        createdAt = now
        updatedAt = now
        self.sourceSession = sourceSession
        self.origin = origin
        self.reinforcement = reinforcement
        self.supersededBy = supersededBy
        self.vector = vector
    }
}

/// 待评估的记忆候选（入库前）
public struct MemoryCandidate: Sendable {
    public let content: String
    public let kind: MemoryKind
    public let topic: String
    public let sourceSession: String
    public let origin: MemoryOrigin
    /// 显式记住等强意图 → 意义度下限
    public let significanceFloor: Float

    public init(content: String, kind: MemoryKind, topic: String,
                sourceSession: String, origin: MemoryOrigin,
                significanceFloor: Float = 0) {
        self.content = content
        self.kind = kind
        self.topic = topic
        self.sourceSession = sourceSession
        self.origin = origin
        self.significanceFloor = significanceFloor
    }
}

/// 对话交互反馈事件（反馈 → 记忆库/RAG 迭代更新的入口）
public struct FeedbackEvent: Sendable {
    public enum FeedbackType: String, Sendable {
        /// 用户纠正（「不对/错了/应该是 X」）
        case correction
        /// 用户显式要求记住
        case rememberRequest
        /// 工具/执行教训（报错→修复的因果）
        case lesson
        /// 用户确认（「对/就这样/正确」）
        case confirmation
    }

    public let type: FeedbackType
    public let sessionID: String
    /// 反馈原文（检测来源）
    public let rawText: String
    /// 蒸馏后的记忆内容（入库正文）
    public let distilled: String
    /// 反馈针对的主题（一致性比对用）
    public let topic: String

    public init(type: FeedbackType, sessionID: String, rawText: String,
                distilled: String, topic: String) {
        self.type = type
        self.sessionID = sessionID
        self.rawText = rawText
        self.distilled = distilled
        self.topic = topic
    }
}

/// 参与会话总结的单轮交换
public struct MemoryExchange: Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// 记忆写入决策
public enum MemoryDecision: Sendable {
    case stored(id: String)
    case merged(existingID: String)
    case superseded(newID: String, oldID: String)
    case rejected(reason: String)
}

/// 反馈处理结果
public struct FeedbackOutcome: Sendable {
    /// 长期记忆决策
    public let memory: MemoryDecision?
    /// RAG 知识库入库切片数（未配置 RAG 时为 nil）
    public let ragChunks: Int?

    public init(memory: MemoryDecision?, ragChunks: Int?) {
        self.memory = memory
        self.ragChunks = ragChunks
    }
}
