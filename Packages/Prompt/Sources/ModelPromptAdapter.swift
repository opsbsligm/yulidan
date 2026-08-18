import Foundation

// MARK: - 模型差异化提示适配

/// 模型差异化提示适配器：按 ModelProfile 对段落集合做确定性变换
///
/// 规则（可叠加，按固定顺序应用）：
/// 1. `toolCallStyle == .none`：移除 tools 段落
/// 2. `toolCallStyle == .jsonFenced`：在 tools 段落末尾追加工具调用格式约定
/// 3. `promptNotes` 非空：追加 "模型说明" 段落（rules 优先级段尾）
public enum ModelPromptAdapter {
    /// 围栏 JSON 工具调用格式约定（jsonFenced 模型）
    public static let jsonFencedDirective = """
    调用工具时，输出 fenced JSON 代码块（```tool 开头），格式：
    ```tool
    {"name": "工具名", "arguments": {…}}
    ```
    一次只输出一个工具调用；收到工具结果后继续推理。
    """

    public static let modelNotesTitle = "模型说明"

    /// 对模板段落应用适配，返回新段落集合（不修改入参）
    public static func adapt(_ sections: [PromptSection], profile: ModelProfile) -> [PromptSection] {
        var result = sections
        switch profile.toolCallStyle {
        case .none:
            result.removeAll { $0.kind == .tools }
        case .jsonFenced:
            result = result.map { section in
                guard section.kind == .tools else { return section }
                let appended = section.template.trimmingCharacters(in: .whitespacesAndNewlines)
                    + "\n\n" + jsonFencedDirective
                return PromptSection(kind: section.kind, title: section.title,
                                     template: appended, priority: section.priority,
                                     enabled: section.enabled)
            }
        case .native:
            break
        }
        if !profile.promptNotes.isEmpty {
            let notes = PromptSection(
                kind: .rules,
                title: modelNotesTitle,
                template: profile.promptNotes.joined(separator: "\n"),
                priority: 90
            )
            result.append(notes)
        }
        return result
    }

    /// 估算渲染后提示词的 token 数（粗略：中文字符≈1 token，ASCII≈0.25 token/字符）
    ///
    /// 用于上下文窗口保护；精确值以模型侧 usage 为准。
    public static func estimateTokens(_ text: String) -> Int {
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x4E00, scalar.value <= 0x9FFF {
                cjk += 1
            } else {
                other += 1
            }
        }
        return cjk + Int(Double(other) * 0.25) + 1
    }
}
