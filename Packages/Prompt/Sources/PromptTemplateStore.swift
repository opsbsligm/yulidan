import CryptoKit
import Foundation

// MARK: - 版本快照

/// 模板版本快照（不可变历史副本）
public struct TemplateSnapshot: Sendable, Codable, Hashable {
    public let name: String
    public let version: Int
    public let template: PromptTemplate
    /// 模板内容指纹（SHA-256，十六进制）
    public let contentHash: String
    public let createdAt: Date
}

// MARK: - 模板存储（actor）

/// 角色模板存储：注册 / 更新（版本快照）/ 查询
///
/// - 每次 `update` 生成 version+1 的不可变快照，保留全部历史（上限 historyLimit 条，FIFO 淘汰）
/// - 内置模板（isBuiltIn）更新时保留 isBuiltIn 标记，用户编辑不会丢失保护属性
public actor PromptTemplateStore {
    private var templates: [String: PromptTemplate] = [:]
    private var history: [String: [Int: TemplateSnapshot]] = [:]
    private let historyLimit: Int

    public init(historyLimit: Int = 32) {
        self.historyLimit = historyLimit
    }

    /// 注册模板；同名已存在时拒绝（用 update 改版本）
    @discardableResult
    public func register(_ template: PromptTemplate) -> Bool {
        guard templates[template.name] == nil else { return false }
        templates[template.name] = template
        recordSnapshot(for: template)
        return true
    }

    /// 更新模板：版本号 +1 并记录快照
    public func update(named name: String, transform: @Sendable (PromptTemplate) -> PromptTemplate) -> PromptTemplate? {
        guard var current = templates[name] else { return nil }
        current = transform(current)
        current.version = (history[name]?.keys.max() ?? 0) + 1
        current.updatedAt = Date()
        current.name = name
        templates[name] = current
        recordSnapshot(for: current)
        return current
    }

    /// 删除模板（含历史）
    @discardableResult
    public func remove(named name: String) -> Bool {
        guard templates.removeValue(forKey: name) != nil else { return false }
        history.removeValue(forKey: name)
        return true
    }

    /// 最新模板
    public func template(named name: String) -> PromptTemplate? {
        templates[name]
    }

    /// 指定版本模板（从快照历史取）
    public func template(named name: String, version: Int) -> PromptTemplate? {
        history[name]?[version]?.template
    }

    /// 某模板全部历史版本（升序）
    public func versions(of name: String) -> [Int] {
        (history[name]?.keys.sorted()) ?? []
    }

    /// 最新快照
    public func latestSnapshot(named name: String) -> TemplateSnapshot? {
        history[name]?.values.max { $0.version < $1.version }
    }

    public func all() -> [PromptTemplate] {
        templates.values.sorted { $0.name < $1.name }
    }

    // MARK: - 私有

    private func recordSnapshot(for template: PromptTemplate) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys] // 键序稳定 → 指纹可复现
        let hash = (try? encoder.encode(template)).map(Self.sha256Hex) ?? "unknown"
        let snapshot = TemplateSnapshot(
            name: template.name,
            version: template.version,
            template: template,
            contentHash: hash,
            createdAt: Date()
        )
        var bucket = history[template.name] ?? [:]
        bucket[template.version] = snapshot
        // FIFO 淘汰最旧版本
        while bucket.count > historyLimit {
            if let oldest = bucket.keys.min() {
                bucket.removeValue(forKey: oldest)
            } else {
                break
            }
        }
        history[template.name] = bucket
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
