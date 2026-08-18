import Foundation

// MARK: - 技能版本管理

/// 一条版本历史记录（内容快照 + 变更说明）
public struct SkillVersionRecord: Codable, Sendable, Identifiable {
    public let version: Int
    public let changeNote: String
    public let changedAt: Date
    public let description: String
    public let instructions: String

    public var id: Int {
        version
    }

    public init(version: Int, changeNote: String, changedAt: Date = Date(),
                description: String, instructions: String) {
        self.version = version
        self.changeNote = changeNote
        self.changedAt = changedAt
        self.description = description
        self.instructions = instructions
    }
}

/// 版本管理：历史快照（versions.json）/ 回滚 / 差异对比
public enum SkillVersioning {
    /// 历史文件上限条数
    public static let maxHistory = 20

    static func historyURL(directory: URL) -> URL {
        directory.appendingPathComponent("versions.json")
    }

    /// 读取历史（旧 → 新）
    public static func loadHistory(directory: URL) -> [SkillVersionRecord] {
        guard
            let data = try? Data(contentsOf: historyURL(directory: directory)),
            let records = try? JSONDecoder().decode([SkillVersionRecord].self, from: data)
        else {
            return []
        }
        return records.sorted { $0.version < $1.version }
    }

    /// 记录一次变更（追加历史，超上限截断最早的）
    public static func record(_ skill: Skill, note: String, directory: URL) throws {
        var history = loadHistory(directory: directory)
        history.append(SkillVersionRecord(version: skill.version, changeNote: note,
                                          description: skill.description, instructions: skill.instructions))
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        let data = try JSONEncoder().encode(history)
        try data.write(to: historyURL(directory: directory), options: .atomic)
    }

    /// 回滚到某版本：以该版本内容生成新版本（版本号 = 当前 + 1）
    /// - Returns: 回滚后的新技能；版本不存在返回 nil
    @discardableResult
    public static func restore(name: String, to version: Int, current: Skill,
                               root: URL = SkillStore.userSkillsDirectory) throws -> Skill? {
        let directory = SkillStore.skillDirectory(for: name, root: root)
        guard let historyRecord = loadHistory(directory: directory).first(where: { $0.version == version }) else {
            return nil
        }
        var restored = current
        restored.description = historyRecord.description
        restored.instructions = historyRecord.instructions
        restored.version = current.version + 1
        restored.source = SkillStore.skillDirectory(for: name, root: root).appendingPathComponent("SKILL.md").path
        try SkillStore.save(restored, to: root)
        try SkillVersioning.record(restored, note: "回滚自 v\(version)", directory: directory)
        return restored
    }

    /// 简化行差异（- 旧 / + 新）
    public static func diff(_ a: String, _ b: String) -> String {
        let al = a.components(separatedBy: "\n")
        let bl = b.components(separatedBy: "\n")
        var out: [String] = []
        let maxLen = max(al.count, bl.count)
        for i in 0 ..< maxLen {
            let la = i < al.count ? al[i] : ""
            let lb = i < bl.count ? bl[i] : ""
            if la == lb {
                continue
            }
            if !la.isEmpty {
                out.append("- \(la)")
            }
            if !lb.isEmpty {
                out.append("+ \(lb)")
            }
        }
        return out.isEmpty ? "（无差异）" : out.joined(separator: "\n")
    }
}
