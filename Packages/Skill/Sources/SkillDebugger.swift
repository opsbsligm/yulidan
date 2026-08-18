import Foundation

// MARK: - 技能调试运行

/// 调试问题
public struct SkillDebugIssue: Sendable {
    public enum Severity: String, Sendable {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// 调试报告
public struct SkillDebugReport: Sendable {
    public let skillName: String
    public let issues: [SkillDebugIssue]
    /// Agent 加载该技能后实际看到的提示词预览（含样例输入）
    public let promptPreview: String

    public var passed: Bool {
        !issues.contains(where: { $0.severity == .error })
    }

    public init(skillName: String, issues: [SkillDebugIssue], promptPreview: String) {
        self.skillName = skillName
        self.issues = issues
        self.promptPreview = promptPreview
    }

    /// 可读文本（CLI / 工具输出）
    public var text: String {
        var lines = ["【技能调试】\(skillName)"]
        if issues.isEmpty {
            lines.append("✅ 结构校验通过")
        } else {
            for issue in issues {
                let icon = issue.severity == .error ? "❌" : "⚠️"
                lines.append("\(icon) \(issue.message)")
            }
        }
        lines.append(passed ? "✅ 调试通过（可安全使用）" : "⛔ 调试未通过（存在 error 级问题）")
        lines.append("")
        lines.append("---- 提示词预览 ----")
        lines.append(promptPreview)
        return lines.joined(separator: "\n")
    }
}

/// 技能调试器：结构校验 + 提示词预览（不依赖 LLM，零成本可重复运行）
public enum SkillDebugger {
    /// 结构校验
    public static func validate(_ skill: Skill) -> [SkillDebugIssue] {
        var issues = nameIssues(skill.name)
        issues.append(contentsOf: descriptionIssues(skill.description))
        issues.append(contentsOf: bodyIssues(skill.instructions))
        issues.append(contentsOf: roundTripIssues(skill))
        return issues
    }

    private static func nameIssues(_ name: String) -> [SkillDebugIssue] {
        if name.isEmpty {
            return [.init(severity: .error, message: "name 为空")]
        }
        if name.count > 64 {
            return [.init(severity: .error, message: "name 超过 64 字符")]
        }
        if name != name.lowercased() || name.contains(" ") {
            return [.init(severity: .warning, message: "name 建议为小写 slug（无空格）")]
        }
        return []
    }

    private static func descriptionIssues(_ description: String) -> [SkillDebugIssue] {
        if description.isEmpty {
            return [.init(severity: .error, message: "description 为空（Agent 无法判断何时使用）")]
        }
        if description.count > 200 {
            return [.init(severity: .warning, message: "description 超过 200 字符，Agent 列表展示会截断")]
        }
        return []
    }

    private static func bodyIssues(_ instructions: String) -> [SkillDebugIssue] {
        if instructions.isEmpty {
            return [.init(severity: .error, message: "instructions 正文为空")]
        }
        var issues: [SkillDebugIssue] = []
        if instructions.count > 20000 {
            issues.append(.init(severity: .warning, message: "instructions 超过 20000 字符，注入提示词开销大"))
        }
        let upper = instructions.uppercased()
        for placeholder in ["TODO", "TBD", "FIXME", "xxx"] where upper.contains(placeholder) {
            issues.append(.init(severity: .warning, message: "正文含未完成的占位符「\(placeholder)」"))
        }
        return issues
    }

    /// frontmatter 往返一致性（序列化 → 再解析，字段应保持）
    private static func roundTripIssues(_ skill: Skill) -> [SkillDebugIssue] {
        guard let roundTrip = SkillStore.parse(SkillStore.serialize(skill), source: skill.source) else {
            return [.init(severity: .error, message: "frontmatter 往返解析失败（name/description 含非法换行？）")]
        }
        if roundTrip.instructions != skill.instructions {
            return [.init(severity: .error, message: "正文序列化往返不一致")]
        }
        return []
    }

    /// 渲染 Agent 加载技能后看到的提示词（含样例输入上下文）
    public static func preview(skill: Skill, sampleInput: String) -> String {
        var lines = ["【技能 \(skill.name)】\(skill.description)", skill.instructions]
        if !sampleInput.isEmpty {
            lines.append("")
            lines.append("---- 当前任务输入（样例） ----")
            lines.append(sampleInput)
        }
        return lines.joined(separator: "\n")
    }

    /// 调试运行：结构校验 + 提示词预览
    public static func debugRun(_ skill: Skill, sampleInput: String = "") -> SkillDebugReport {
        SkillDebugReport(skillName: skill.name, issues: validate(skill),
                         promptPreview: preview(skill: skill, sampleInput: sampleInput))
    }
}
