import Foundation

// MARK: - 错误

public enum PromptError: Error, Sendable {
    /// 模板不存在
    case templateNotFound(String)
    /// 模板指定版本不存在
    case versionNotFound(template: String, version: Int)
    /// 模板内容为空（无有效段落或渲染后为空）
    case emptyTemplate(String)
}

// MARK: - 模板文本渲染

/// 模板文本渲染器：条件块 → 变量替换（v1 不支持块嵌套，文档约定）
public enum TemplateRenderer {
    /// 渲染单个段落文本
    ///
    /// 顺序：先展开条件块（避免块内 `{{var}}` 被提前替换后残留块标记），再替换变量。
    /// 缺失变量渲染为空串；条件块无内容则整块删除（含包裹空白行收敛）。
    public static func render(_ template: String, context: PromptContext) -> String {
        let blocksExpanded = expandBlocks(template, blocks: context.blocks)
        let stripped = stripUnboundBlocks(blocksExpanded)
        let substituted = substituteVariables(stripped, variables: context.variables)
        return collapseEmptyLines(substituted).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 渲染整个模板为系统提示词（段落按 effectiveSections 顺序，以 `## 标题` 分节）
    public static func renderTemplate(_ template: PromptTemplate, context: PromptContext) throws -> String {
        let rendered: [String] = template.effectiveSections.compactMap { section in
            let text = render(section.template, context: context)
            guard !text.isEmpty else { return nil }
            return section.title.isEmpty ? text : "## \(section.title)\n\(text)"
        }
        let joined = rendered.joined(separator: "\n\n")
        guard !joined.isEmpty else {
            throw PromptError.emptyTemplate(template.name)
        }
        return joined
    }

    // MARK: - 私有步骤

    private static func expandBlocks(_ text: String, blocks: [String: String]) -> String {
        var result = text
        // 按块名长度降序处理，避免短名是长名前缀时的误匹配
        for name in blocks.keys.sorted(by: { $0.count > $1.count }) {
            result = replaceBlock(name: name, content: blocks[name] ?? "", in: result)
        }
        return result
    }

    /// 移除未提供内容的良构条件块（`{{#name}}...{{/name}}`，name 限字母/数字/下划线）
    ///
    /// 提示词中不允许残留模板标记：已绑定块由 expandBlocks 处理，此处兜底未绑定块。
    /// 无闭合标记的坏块不受影响（保留原文，交由人工排查）。
    private static func stripUnboundBlocks(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\{\\{#([A-Za-z0-9_]+)\\}\\}[\\s\\S]*?\\{\\{/\\1\\}\\}",
            with: "",
            options: .regularExpression
        )
    }

    /// 替换 `{{#name}}...{{/name}}`：有内容展开为内容，无内容整块删除
    private static func replaceBlock(name: String, content: String, in text: String) -> String {
        let open = "{{#\(name)}}"
        let close = "{{/\(name)}}"
        var result = ""
        var rest = text
        while let openRange = rest.range(of: open) {
            result += rest[..<openRange.lowerBound]
            guard let closeRange = rest[openRange.upperBound...].range(of: close) else {
                // 无闭合标记：保留原文，避免误删
                return result + rest[openRange.lowerBound...]
            }
            if !content.isEmpty {
                result += content
            }
            rest = String(rest[closeRange.upperBound...])
        }
        return result + rest
    }

    private static func substituteVariables(_ text: String, variables: [String: String]) -> String {
        var result = text
        for key in variables.keys.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: variables[key] ?? "")
        }
        // 未提供变量的占位符渲染为空
        return removeUnboundPlaceholders(result)
    }

    /// 扫描 `{{name}}` 形式的未绑定占位符并移除（name：字母/数字/下划线，可含空白）
    private static func removeUnboundPlaceholders(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == "{", i + 1 < chars.count, chars[i + 1] == "{" {
                if let close = placeholderClose(after: i + 2, in: chars) {
                    i = close + 2
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    /// 从 start 起找 `}}` 闭合位（前须有合法 name）；无则返回 nil
    private static func placeholderClose(after start: Int, in chars: [Character]) -> Int? {
        var j = start
        var sawName = false
        while j < chars.count {
            let c = chars[j]
            if c == "}" {
                guard sawName, j + 1 < chars.count, chars[j + 1] == "}" else { return nil }
                return j
            }
            if c.isLetter || c.isNumber || c == "_" {
                sawName = true
            } else if !c.isWhitespace {
                return nil
            }
            j += 1
        }
        return nil
    }

    /// 3 行以上连续空行收敛为 1 行
    private static func collapseEmptyLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n[ \\t]*\\n[ \\t]*\\n[ \\t]*\\n+", with: "\\n\\n", options: .regularExpression)
    }
}
