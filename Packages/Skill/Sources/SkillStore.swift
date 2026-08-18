import Foundation

// MARK: - SKILL.md 解析与加载

/// 技能文件存储：目录扫描 + frontmatter 解析
public enum SkillStore {
    /// 测试钩子：覆盖用户技能目录
    public nonisolated(unsafe) static var userSkillsDirectoryOverride: URL?

    /// 用户技能目录：~/.harness/skills/<技能名>/SKILL.md
    /// 解析优先级：测试覆盖 > HARNESS_HOME 环境变量（隔离运行）> 用户主目录
    public static var userSkillsDirectory: URL {
        if let override = userSkillsDirectoryOverride {
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let base: URL = if let envHome = ProcessInfo.processInfo.environment["HARNESS_HOME"], !envHome.isEmpty {
            URL(fileURLWithPath: (envHome as NSString).expandingTildeInPath)
        } else {
            FileManager.default.homeDirectoryForCurrentUser
        }
        let dir = base.appendingPathComponent(".harness/skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 解析单个 SKILL.md 文本（frontmatter + 正文）
    ///
    /// 格式：
    /// ```
    /// ---
    /// name: git-commit
    /// description: 写约定式提交信息
    /// tags: git, commit
    /// ---
    /// 正文……
    /// ```
    /// 缺少闭合 frontmatter 或缺少 name → 返回 nil（调用方跳过并记录）。
    public static func parse(_ text: String, source: String) -> Skill? {
        var lines = text.components(separatedBy: "\n")
        // 允许首部空行
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var frontmatter: [String: String] = [:]
        var index = 1
        var closed = false
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closed = true
                index += 1
                break
            }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    frontmatter[key] = value
                }
            }
            index += 1
        }
        guard closed else { return nil }
        guard let name = frontmatter["name"], !name.isEmpty else { return nil }
        let body = lines[index...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = (frontmatter["tags"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Skill(name: name,
                     description: frontmatter["description"] ?? "",
                     instructions: body,
                     tags: tags,
                     source: source,
                     version: Int(frontmatter["version"] ?? "1") ?? 1)
    }

    /// 序列化为 SKILL.md 文本（导出/导入用；描述与标签压成单行）
    public static func serialize(_ skill: Skill) -> String {
        func oneLine(_ value: String) -> String {
            value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        }
        var lines = ["---", "name: \(oneLine(skill.name))", "description: \(oneLine(skill.description))"]
        if !skill.tags.isEmpty {
            lines.append("tags: \(skill.tags.map(oneLine).joined(separator: ", "))")
        }
        if skill.version > 1 {
            lines.append("version: \(skill.version)")
        }
        lines.append("---")
        lines.append(skill.instructions)
        return lines.joined(separator: "\n") + "\n"
    }

    /// 技能目录：<root>/<技能名>
    public static func skillDirectory(for name: String, root: URL = userSkillsDirectory) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    /// 保存技能到用户目录（<root>/<name>/SKILL.md；已存在则覆盖）
    @discardableResult
    public static func save(_ skill: Skill, to root: URL = userSkillsDirectory) throws -> URL {
        let dir = skillDirectory(for: skill.name, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("SKILL.md")
        try serialize(skill).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// 删除技能目录
    @discardableResult
    public static func delete(_ name: String, from root: URL = userSkillsDirectory) -> Bool {
        guard FileManager.default.fileExists(atPath: skillDirectory(for: name, root: root).path) else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: skillDirectory(for: name, root: root))
            return true
        } catch {
            return false
        }
    }

    /// 从目录加载全部技能（每个子目录含一个 SKILL.md；无效条目跳过）
    /// - Returns: 按 name 排序的技能列表
    public static func load(from directory: URL) -> [Skill] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles]) else {
            return []
        }
        let skills = entries.compactMap { entry -> Skill? in
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let fileURL = isDir ? entry.appendingPathComponent("SKILL.md") : entry
            guard fileURL.pathExtension == "md",
                  let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return nil
            }
            return parse(text, source: fileURL.path)
        }
        return skills.sorted { $0.name < $1.name }
    }
}
