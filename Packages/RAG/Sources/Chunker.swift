import Foundation

// MARK: - 切片分块

/// 文档切片（保留来源溯源信息：文档 ID + 序号 + 原文字符区间）
public struct RAGChunk: Sendable, Identifiable {
    public let id: String
    public let documentID: String
    public let index: Int
    public let text: String
    /// 在原文中的字符区间（相对文档全文，溯源引用用）
    public let charStart: Int
    public let charEnd: Int

    public init(id: String = UUID().uuidString,
                documentID: String,
                index: Int,
                text: String,
                charStart: Int,
                charEnd: Int) {
        self.id = id
        self.documentID = documentID
        self.index = index
        self.text = text
        self.charStart = charStart
        self.charEnd = charEnd
    }
}

/// 切片策略参数
public struct ChunkingOptions: Sendable {
    /// 目标块大小（字符）
    public var targetSize: Int
    /// 相邻块重叠（字符）
    public var overlap: Int
    /// 是否按段落边界优先切分
    public var paragraphAware: Bool

    public init(targetSize: Int = 800, overlap: Int = 120, paragraphAware: Bool = true) {
        self.targetSize = targetSize
        self.overlap = overlap
        self.paragraphAware = paragraphAware
    }
}

/// 切片器：段落感知 + 目标大小 + 重叠
public enum Chunker {
    /// 把文档全文切成有序块（空文本 → 空数组）
    public static func chunk(_ text: String, documentID: String, options: ChunkingOptions = .init()) -> [RAGChunk] {
        guard !text.isEmpty, options.targetSize > 0 else { return [] }
        let overlap = max(0, min(options.overlap, options.targetSize / 2))
        // 按段落预切（段落本身超限时内部再硬切）
        let paragraphs = options.paragraphAware ? splitParagraphs(text) : [text]
        var pieces: [String] = []
        var current = ""
        for para in paragraphs {
            if para.isEmpty {
                continue
            }
            if !current.isEmpty, current.count + para.count + 1 > options.targetSize {
                pieces.append(current)
                current = para
            } else {
                current = current.isEmpty ? para : current + "\n" + para
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        // 超长段落硬切 + 重叠
        var finalPieces: [String] = []
        for piece in pieces {
            if piece.count <= options.targetSize {
                finalPieces.append(piece)
                continue
            }
            let chars = Array(piece)
            var i = 0
            while i < chars.count {
                finalPieces.append(String(chars[i ..< min(i + options.targetSize, chars.count)]))
                if i + options.targetSize < chars.count {
                    i += options.targetSize - overlap
                } else {
                    break
                }
            }
        }
        // 计算字符区间（相对原文，近似定位：按片段顺序在原文中查找）
        return locateInSource(finalPieces, source: text, documentID: documentID)
    }

    /// 段落切分（空行分隔；单行过长保持原样）
    public static func splitParagraphs(_ text: String) -> [String] {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 在原文中顺序定位各切片（NSString 高效子串查找；区间为近似溯源位置）
    private static func locateInSource(_ pieces: [String], source: String, documentID: String) -> [RAGChunk] {
        let nsSource = source as NSString
        let sourceLength = nsSource.length
        var result: [RAGChunk] = []
        var searchFrom = 0
        for (idx, piece) in pieces.enumerated() {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
            var start = searchFrom
            if trimmed.length > 0, searchFrom <= sourceLength {
                let fromRange = NSRange(location: min(searchFrom, sourceLength),
                                        length: max(0, sourceLength - min(searchFrom, sourceLength)))
                let found = nsSource.range(of: trimmed as String, options: [], range: fromRange)
                if found.location != NSNotFound {
                    start = found.location
                    searchFrom = found.location + trimmed.length
                }
            }
            let end = min(sourceLength, start + (piece as NSString).length)
            result.append(RAGChunk(documentID: documentID, index: idx, text: piece,
                                   charStart: start, charEnd: max(start, end)))
            searchFrom = max(searchFrom, end)
        }
        return result
    }
}
