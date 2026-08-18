import Foundation

// MARK: - 文档加载与解析

/// 加载完成的文档（解析为纯文本，保留来源与元数据）
public struct LoadedDocument: Sendable, Identifiable {
    public let id: String
    /// 来源（文件路径或自定义标识）
    public let source: String
    /// 标题（默认取文件名，可覆盖）
    public let title: String
    /// 纯文本正文
    public let text: String
    /// 元数据（检索过滤用，如 source_tag）
    public let metadata: [String: String]

    public init(id: String = UUID().uuidString,
                source: String,
                title: String? = nil,
                text: String,
                metadata: [String: String] = [:]) {
        self.id = id
        self.source = source
        self.title = title ?? URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        self.text = text
        self.metadata = metadata
    }
}

/// 文档加载错误
public enum DocumentLoadError: Error, Sendable {
    case notFound(String)
    case unsupportedExtension(String)
    case tooLarge(bytes: Int, limit: Int)
    case decodeFailed(String)
}

/// 文档加载器：支持 .txt / .md / .markdown / .html / .json
public enum DocumentLoader {
    /// 单文件上限（字节）
    public static let maxBytes = 5_000_000
    public static let supportedExtensions = ["txt", "md", "markdown", "html", "htm", "json"]

    /// 从路径加载并解析为纯文本
    public static func load(path: String) throws -> LoadedDocument {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentLoadError.notFound(url.path)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? Int) ?? 0
        guard size <= maxBytes else {
            throw DocumentLoadError.tooLarge(bytes: size, limit: maxBytes)
        }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw DocumentLoadError.unsupportedExtension(ext)
        }
        let rawText: String = switch ext {
        case "html", "htm":
            stripHTML(String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "")
        case "json":
            extractJSONTexts(data)
        default:
            String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        }
        let text = ext == "md" || ext == "markdown" ? stripMarkdown(rawText) : rawText
        return LoadedDocument(source: url.path, text: text)
    }

    /// 直接文本加载（测试/内存文档用）
    public static func loadText(_ text: String, source: String, title: String? = nil,
                                metadata: [String: String] = [:]) -> LoadedDocument {
        LoadedDocument(source: source, title: title, text: text, metadata: metadata)
    }

    // MARK: 解析

    /// Markdown → 纯文本（去标记语法，保正文与标题文字）
    public static func stripMarkdown(_ text: String) -> String {
        var out = text
        // 代码块：保留内容
        out = out.replacingOccurrences(of: "```[a-zA-Z0-9_+-]*", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "```\n?", with: "\n", options: .literal)
        // 图片 → 空；链接 [text](url) → text
        out = out.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        // 行内代码/粗斜体/删除线
        out = out.replacingOccurrences(of: "`{1,3}", with: "", options: .literal)
        out = out.replacingOccurrences(of: "(?<!\\*)\\*{1,3}([^*\\n]+)\\*{1,3}(?!\\*)", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "~~([^~\\n]+)~~", with: "$1", options: .regularExpression)
        // 标题/引用/列表标记
        out = out.replacingOccurrences(of: "(?m)^[ \\t]*#{1,6}[ \\t]*", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?m)^[ \\t]*>[ \\t]?", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?m)^[ \\t]*[-*+][ \\t]+", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?m)^[ \\t]*\\d+[.)][ \\t]+", with: "", options: .regularExpression)
        // 表格分隔行
        out = out.replacingOccurrences(of: "(?m)^[ \\t]*\\|?[ \\t:|-]+\\|?[ \\t]*$", with: "", options: .regularExpression)
        // 围栏/水平线
        out = out.replacingOccurrences(of: "(?m)^[ \\t]*([-*_])[ \\t]*(\\1[ \\t]*){2,}$", with: "", options: .regularExpression)
        // 空行压缩
        out = out.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML → 纯文本（去标签与脚本/样式块）
    public static func stripHTML(_ html: String) -> String {
        var out = html
        out = out.replacingOccurrences(of: "(?s)<(script|style|head)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?s)<!--.*?-->", with: " ", options: .regularExpression)
        // 块级标签转行
        out = out.replacingOccurrences(of: "(?i)</?(p|div|br|li|tr|h[1-6]|section|article|table)[^>]*>", with: "\n", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?i)<[^>]+>", with: "", options: .regularExpression)
        // 常见实体
        for (entity, text) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"] {
            out = out.replacingOccurrences(of: entity, with: text, options: .literal)
        }
        out = out.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// JSON → 文本（递归抽取全部字符串值，数组/对象扁平化为「键: 值」行）
    public static func extractJSONTexts(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        var lines: [String] = []
        walk(obj, key: nil, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func walk(_ value: Any, key: String?, into lines: inout [String]) {
        switch value {
        case let dict as [String: Any]:
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                walk(v, key: k, into: &lines)
            }
        case let arr as [Any]:
            for v in arr {
                walk(v, key: key, into: &lines)
            }
        case let s as String:
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(key.map { "\($0): \(s)" } ?? s)
            }
        case let n as NSNumber:
            lines.append(key.map { "\($0): \(n)" } ?? n.description)
        default:
            break
        }
    }
}
