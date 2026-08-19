import Foundation
import RAG

// MARK: - 技能进化（Hermes 范式：重复任务 → 自动评估 → 自动生成 → 保存 → 复用）

/// 单次任务观测（对话/CLI 任务结束时上报）
public struct TaskObservation: Codable, Sendable {
    public let sessionID: String
    /// 任务原文（用户请求）
    public let task: String
    /// 任务中按序调用的工具名
    public let toolNames: [String]
    public let succeeded: Bool
    public let observedAt: Date

    public init(sessionID: String, task: String, toolNames: [String] = [],
                succeeded: Bool = true, observedAt: Date = Date()) {
        self.sessionID = sessionID
        self.task = task
        self.toolNames = toolNames
        self.succeeded = succeeded
        self.observedAt = observedAt
    }
}

/// 进化引擎配置
public struct EvolutionConfig: Sendable {
    /// 相似任务累计达到该次数才生成技能候选
    public var minRepetition: Int
    /// 任务文本相似度阈值（HashingVectorizer 余弦）
    public var similarityThreshold: Float
    /// 最短任务长度（过滤碎片消息）
    public var minTaskLength: Int

    public init(minRepetition: Int = 2, similarityThreshold: Float = 0.6, minTaskLength: Int = 8) {
        self.minRepetition = minRepetition
        self.similarityThreshold = similarityThreshold
        self.minTaskLength = minTaskLength
    }
}

/// 自动生成的技能候选
public struct SkillCandidate: Sendable {
    public let name: String
    public let description: String
    public let instructions: String
    public let tags: [String]
    /// 支撑该候选的观测任务数
    public let evidenceCount: Int
    /// 代表性任务样例（最多 3 条）
    public let sampleTasks: [String]

    public init(name: String, description: String, instructions: String, tags: [String],
                evidenceCount: Int, sampleTasks: [String]) {
        self.name = name
        self.description = description
        self.instructions = instructions
        self.tags = tags
        self.evidenceCount = evidenceCount
        self.sampleTasks = sampleTasks
    }
}

/// 技能进化：相似度聚类 + 候选生成（零模型、确定性）
public enum SkillEvolution {
    private static let vectorizer = HashingVectorizer()

    /// 任务文本归一化（小写 + 去标点空白，保留中英文数字）
    public static func normalize(_ task: String) -> String {
        var out = ""
        for ch in task.lowercased() where ch.isLetter || ch.isNumber {
            out.append(ch)
        }
        return out
    }

    /// 相似度聚类（贪心：与组首样本相似度 ≥ 阈值 → 同组）
    public static func cluster(_ observations: [TaskObservation], threshold: Float) -> [[TaskObservation]] {
        var groups: [(anchorVector: [Float], anchorTask: String, members: [TaskObservation])] = []
        for obs in observations {
            let normalized = normalize(obs.task)
            guard normalized.count >= 8 else { continue }
            let vector = vectorizer.embed(normalized)
            var merged = false
            for (i, group) in groups.enumerated() where VectorMath.cosine(group.anchorVector, vector) >= threshold {
                groups[i].members.append(obs)
                merged = true
                break
            }
            if !merged {
                groups.append((vector, obs.task, [obs]))
            }
        }
        return groups.map(\.members)
    }

    /// 由一个任务簇生成技能候选；簇内任务过少或无共性 → nil
    public static func makeCandidate(from cluster: [TaskObservation], minRepetition: Int) -> SkillCandidate? {
        guard cluster.count >= minRepetition else { return nil }
        let tasks = cluster.map(\.task)
        let first = tasks[0]
        let name = slugify(first)
        guard !name.isEmpty else { return nil }
        // 工具序列取首个观测中出现的顺序（去重保序）
        var toolSeq: [String] = []
        for obs in cluster {
            for tool in obs.toolNames where !toolSeq.contains(tool) {
                toolSeq.append(tool)
            }
        }
        let description = "自动沉淀技能：\(String(first.prefix(40)))"
        var lines: [String] = ["# \(name)", "", "适用场景：\(description)", ""]
        if toolSeq.isEmpty {
            lines.append("## 步骤")
            lines.append("1. 参照样例任务完成同类请求：")
            for sample in tasks.prefix(3) {
                lines.append("   - \(String(sample.prefix(80)))")
            }
        } else {
            lines.append("## 推荐工具序列")
            lines.append("\(toolSeq.joined(separator: " → "))")
            lines.append("")
            lines.append("## 样例任务")
            for sample in tasks.prefix(3) {
                lines.append("- \(String(sample.prefix(80)))")
            }
        }
        lines.append("")
        lines.append("## 说明")
        lines.append("- 本技能由系统从 \(cluster.count) 次相似任务观察自动生成，可编辑完善。")
        let tags = toolSeq.isEmpty ? ["auto"] : Array(Set(toolSeq).sorted().prefix(3))
        return SkillCandidate(name: name, description: description,
                              instructions: lines.joined(separator: "\n"),
                              tags: tags, evidenceCount: cluster.count,
                              sampleTasks: Array(tasks.prefix(3)))
    }

    /// 常见功能词（不入 slug，避免无意义词占用 prefix 位置）
    private static let stopWords: Set<String> = ["the", "a", "an", "to", "of", "for", "and", "please"]

    /// 任务文本 → 技能 slug（ASCII 内容词序 → 连字符，取前 4 个；无 ASCII 词 → auto-<8 位稳定哈希>）
    /// 注意：分词必须基于原始小写文本（normalize 会先剥掉空白，词边界即丢失）
    public static func slugify(_ task: String) -> String {
        var words: [String] = []
        var word = ""
        for ch in task.lowercased() {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                word.append(ch)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty {
            words.append(word)
        }
        let contentWords = words.filter { !stopWords.contains($0) }
        let slug = contentWords.prefix(4).joined(separator: "-")
        if !slug.isEmpty {
            return String(slug.prefix(48))
        }
        let normalized = normalize(task)
        let hash = String(format: "%08x", UInt32(HashingVectorizer.fnv1a(normalized) % 0xFFFF_FFFF))
        return "auto-\(hash)"
    }
}

/// 观测窗口持久化（nil = 仅内存，单元测试隔离用）
public protocol ObservationStore: Sendable {
    func load() -> [TaskObservation]
    func save(_ observations: [TaskObservation])
}

/// JSON 文件观测存储（原子写；并发进程 last-writer-wins，上限截断后整体重写）
public struct JSONObservationStore: ObservationStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [TaskObservation] {
        guard let data = try? Data(contentsOf: url),
              let observations = try? JSONDecoder().decode([TaskObservation].self, from: data) else {
            return []
        }
        return observations
    }

    public func save(_ observations: [TaskObservation]) {
        guard let data = try? JSONEncoder().encode(observations) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// 技能进化引擎：观测任务 → 评估重复模式 → 自动生成并保存技能（进注册表可复用）
public actor SkillEvolutionEngine {
    public let config: EvolutionConfig
    private let registry: SkillRegistry
    private let observationStore: (any ObservationStore)?
    /// 技能保存根目录（nil = SkillStore 默认用户目录；测试可注入隔离目录）
    private let saveRoot: URL?
    private var observations: [TaskObservation] = []
    /// 已生成过的技能名（防止重复生成）
    private var generatedNames: Set<String> = []

    public init(registry: SkillRegistry, config: EvolutionConfig = .init(),
                observationStore: (any ObservationStore)? = nil, saveRoot: URL? = nil) {
        self.registry = registry
        self.config = config
        self.observationStore = observationStore
        self.saveRoot = saveRoot
        if let observationStore {
            // 恢复上次进程留下的观测窗口（CLI 短进程跨 run 累计重复任务）
            observations = Array(observationStore.load().suffix(200))
        }
    }

    /// 上报一次任务观测
    public func observe(sessionID: String, task: String, toolNames: [String] = [], succeeded: Bool = true) {
        guard Self.minLengthOk(task, config: config) else { return }
        observations.append(TaskObservation(sessionID: sessionID, task: task,
                                            toolNames: toolNames, succeeded: succeeded))
        if observations.count > 200 {
            observations.removeFirst(observations.count - 200)
        }
        observationStore?.save(observations)
    }

    private static func minLengthOk(_ task: String, config: EvolutionConfig) -> Bool {
        SkillEvolution.normalize(task).count >= config.minTaskLength
    }

    /// 评估当前观测：满足重复阈值的簇 → 生成候选 → 保存 + 注册；返回本轮新生成的候选
    @discardableResult
    public func evaluate() async -> [SkillCandidate] {
        let clusters = SkillEvolution.cluster(observations, threshold: config.similarityThreshold)
        var created: [SkillCandidate] = []
        for cluster in clusters {
            guard let candidate = SkillEvolution.makeCandidate(from: cluster, minRepetition: config.minRepetition)
            else {
                continue
            }
            if generatedNames.contains(candidate.name) {
                continue
            }
            if await (registry.skill(named: candidate.name)) != nil {
                generatedNames.insert(candidate.name)
                continue
            }
            do {
                var skill = Skill(name: candidate.name, description: candidate.description,
                                  instructions: candidate.instructions, tags: candidate.tags,
                                  source: "auto")
                let root = saveRoot ?? SkillStore.userSkillsDirectory
                let fileURL = try SkillStore.save(skill, to: root)
                skill.source = fileURL.path
                try? SkillVersioning.record(skill, note: "自动生成（\(candidate.evidenceCount) 次相似任务）",
                                            directory: SkillStore.skillDirectory(for: skill.name, root: root))
                _ = await registry.register(skill)
                generatedNames.insert(candidate.name)
                created.append(candidate)
            } catch {
                // 保存失败不阻塞其它候选（下轮再试）
                continue
            }
        }
        return created
    }

    /// 测试/调试：重置观测窗口
    public func reset() {
        observations.removeAll()
    }

    public var pendingObservationCount: Int {
        observations.count
    }
}

// MARK: - 进程级共享实例

/// 进程级共享进化引擎（App/CLI 同一份；技能落 ~/.harness/skills）
public actor SharedSkillEvolution {
    public static let shared = SharedSkillEvolution()

    private var engine: SkillEvolutionEngine?

    public func get(registry: SkillRegistry, config: EvolutionConfig = .init()) -> SkillEvolutionEngine {
        if let engine {
            return engine
        }
        // 生产入口启用观测持久化：CLI 每次 run 都是新进程，窗口必须落盘才能跨 run 累计
        let store = JSONObservationStore(
            url: SkillStore.userSkillsDirectory.appendingPathComponent("observations.json")
        )
        let engine = SkillEvolutionEngine(registry: registry, config: config, observationStore: store)
        self.engine = engine
        return engine
    }

    /// 测试用
    public func replace(_ engine: SkillEvolutionEngine) {
        self.engine = engine
    }
}
