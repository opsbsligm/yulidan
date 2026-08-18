import Foundation

// MARK: - 向量化

/// 向量化器协议（可替换实现；内置为确定性特征哈希，零外部依赖）
public protocol TextVectorizer: Sendable {
    /// 向量维度
    var dimensions: Int { get }
    /// 文本 → L2 归一化向量
    func embed(_ text: String) -> [Float]
}

/// 余弦相似度（两向量须等维）
public enum VectorMath {
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0 ..< a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = (normA.squareRoot() * normB.squareRoot())
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}

/// 确定性特征哈希向量化器
///
/// 原理：文本切分为词元（ASCII 单词 + CJK 单字 + 二元组），
/// 每个词元经 FNV-1a 哈希映射到固定维度桶并累加权重（词频），最后 L2 归一化。
/// 无随机性、无模型依赖，同一文本跨进程/跨平台向量一致，适合本地离线 RAG 基线。
public struct HashingVectorizer: TextVectorizer {
    public let dimensions: Int

    public init(dimensions: Int = 512) {
        self.dimensions = max(16, dimensions)
    }

    public func embed(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        for token in Self.tokenize(text) {
            let bucket = Int(Self.fnv1a(token) % UInt64(dimensions))
            // 符号位用于缓解哈希碰撞（signed hashing）
            let sign: Float = (Self.fnv1a(token + "#") & 1) == 0 ? 1 : -1
            vector[bucket] += sign
        }
        return Self.l2Normalize(vector)
    }

    /// 词元化：ASCII 单词（小写）+ CJK 单字 + CJK 二元组
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        let lower = text.lowercased()
        var word = [Character]()
        var cjkPrev: Character?
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                if isCJK(ch) {
                    flushWord(&word, &tokens)
                    tokens.append(String(ch))
                    if let prev = cjkPrev {
                        tokens.append(String(prev) + String(ch))
                    }
                    cjkPrev = ch
                } else {
                    cjkPrev = nil
                    word.append(ch)
                }
            } else {
                flushWord(&word, &tokens)
                cjkPrev = nil
            }
        }
        flushWord(&word, &tokens)
        return tokens
    }

    private static func flushWord(_ word: inout [Character], _ tokens: inout [String]) {
        if word.count >= 2 {
            tokens.append(String(word))
        }
        word.removeAll(keepingCapacity: true)
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00 ... 0x9FFF).contains(v) // CJK 统一表意
            || (0x3400 ... 0x4DBF).contains(v) // 扩展 A
            || (0x3040 ... 0x30FF).contains(v) // 日文假名
            || (0xAC00 ... 0xD7AF).contains(v) // 韩文
    }

    /// FNV-1a 64 位
    public static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return hash
    }

    private static func l2Normalize(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        for x in v {
            norm += x * x
        }
        guard norm > 0 else { return v }
        let inv = 1 / norm.squareRoot()
        return v.map { $0 * inv }
    }
}
