import Foundation

// MARK: - 技能注册表

/// 技能注册表（actor）：注册 / 检索 / 系统提示词列表
public actor SkillRegistry {
    private var skills: [String: Skill] = [:]

    public init() {}

    public var count: Int {
        skills.count
    }

    /// 注册技能（重名覆盖）；返回是否为全新注册
    @discardableResult
    public func register(_ skill: Skill) -> Bool {
        let existed = skills[skill.name] != nil
        skills[skill.name] = skill
        return !existed
    }

    @discardableResult
    public func remove(_ name: String) -> Skill? {
        skills.removeValue(forKey: name)
    }

    public func skill(named name: String) -> Skill? {
        skills[name]
    }

    /// 全部技能（按 name 排序）
    public func all() -> [Skill] {
        skills.values.sorted { $0.name < $1.name }
    }

    /// 关键词检索：name / description / tags 子串匹配（忽略大小写）；空查询返回全部
    public func search(_ query: String) -> [Skill] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all() }
        return all().filter { skill in
            skill.name.lowercased().contains(q)
                || skill.description.lowercased().contains(q)
                || skill.tags.contains { $0.lowercased().contains(q) }
        }
    }

    /// 系统提示词 / list_skills 用列表（每行：name — description）
    public func promptListing() -> String {
        all().map { "- \($0.name) — \($0.description)" }.joined(separator: "\n")
    }
}
