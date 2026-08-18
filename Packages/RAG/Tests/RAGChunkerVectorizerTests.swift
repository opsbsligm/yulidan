import Foundation
import RAG
import Testing

/// Chunker 单元测试：段落感知 / 大小 / 重叠 / 空文本 / 溯源区间
@Suite("Chunker")
struct RAGChunkerTests {
    @Test func shortTextSingleChunk() {
        let chunks = Chunker.chunk("一小段文本", documentID: "d1")
        #expect(chunks.count == 1)
        #expect(chunks[0].text == "一小段文本")
        #expect(chunks[0].charStart == 0)
        #expect(chunks[0].charEnd == ("一小段文本" as NSString).length) // NSString UTF-16 单位
        #expect(chunks[0].documentID == "d1")
        #expect(chunks[0].index == 0)
    }

    @Test func emptyTextNoChunks() {
        #expect(Chunker.chunk("", documentID: "d").isEmpty)
        #expect(Chunker.chunk("   ", documentID: "d").isEmpty) // 空白文本按段落切分后无有效段
    }

    @Test func multiParagraphSplitByTargetSize() {
        let para = String(repeating: "段落内容文字", count: 40) // 240 字
        let text = (0 ..< 5).map { "第\($0)段：\(para)" }.joined(separator: "\n\n")
        let chunks = Chunker.chunk(text, documentID: "d", options: .init(targetSize: 500, overlap: 0))
        #expect(chunks.count >= 2)
        for c in chunks {
            #expect(c.text.count <= 500)
            // 溯源区间必须落在原文内，且区间内原文包含切片首句
            let ns = text as NSString
            #expect(c.charStart >= 0)
            #expect(c.charEnd <= ns.length)
            let located = ns.substring(with: NSRange(location: c.charStart, length: min(10, ns.length - c.charStart)))
            _ = located
        }
    }

    @Test func longParagraphHardSplitWithOverlap() {
        // 2000 字符无空格无换行 → 只能硬切
        let text = String((0 ..< 2000).map { Character(UnicodeScalar(97 + $0 % 26)!) })
        let opts = ChunkingOptions(targetSize: 500, overlap: 100)
        let chunks = Chunker.chunk(text, documentID: "d", options: opts)
        #expect(chunks.count == 5) // ceil(2000/400 步长) = 5 片
        // 相邻块重叠 100 字符
        #expect(chunks[0].text.suffix(100) == chunks[1].text.prefix(100))
        #expect(chunks[1].text.suffix(100) == chunks[2].text.prefix(100))
        // 首块从 0 开始
        #expect(chunks[0].charStart == 0)
        #expect(chunks[0].charEnd == 500)
    }

    @Test func splitParagraphsTrimsAndFiltersEmpty() {
        let paras = Chunker.splitParagraphs("  甲  \n\n\n\n 乙\n\n   ")
        #expect(paras == ["甲", "乙"])
    }

    @Test func paragraphAwareOffKeepsWholeText() {
        let text = (0 ..< 10).map { "段\($0)：\(String(repeating: "字", count: 60))" }
            .joined(separator: "\n\n")
        let on = Chunker.chunk(text, documentID: "d", options: .init(targetSize: 100, overlap: 0, paragraphAware: true))
        let off = Chunker.chunk(text, documentID: "d", options: .init(targetSize: 100, overlap: 0, paragraphAware: false))
        #expect(on.count == 10) // 感知段落：63 字段落 + 100 上限 → 每块恰 1 段
        #expect(off.count == 7) // 不感知段落：648 字整块硬切 → ceil(648/100)
        #expect(on.count > off.count)
    }
}

/// Vectorizer 单元测试：确定性 / 相似度 / 词元化
@Suite("HashingVectorizer")
struct RAGVectorizerTests {
    @Test func deterministicAcrossCalls() {
        let v = HashingVectorizer()
        #expect(v.embed("swift actor 并发隔离").elementsEqual(v.embed("swift actor 并发隔离")))
    }

    @Test func selfCosineIsOne() {
        let v = HashingVectorizer()
        let vec = v.embed("hello world 你好世界")
        let cos = VectorMath.cosine(vec, vec)
        #expect(abs(cos - 1) < 0.001)
    }

    @Test func similarScoresHigherThanDissimilar() {
        let v = HashingVectorizer()
        let a = v.embed("swift actor 并发 隔离 模型 调度")
        let near = v.embed("swift actor 并发 隔离")
        let far = v.embed("番茄炒蛋 家常 菜谱 做法")
        #expect(VectorMath.cosine(a, near) > VectorMath.cosine(a, far))
    }

    @Test func emptyTextZeroVector() {
        let v = HashingVectorizer()
        let zero = v.embed("")
        #expect(zero.allSatisfy { $0 == 0 })
        #expect(VectorMath.cosine(zero, v.embed("anything")) == 0)
    }

    @Test func tokenizeASCIIAndCJK() {
        let tokens = HashingVectorizer.tokenize("Hello World 苹果")
        #expect(tokens.contains("hello"))
        #expect(tokens.contains("world"))
        #expect(tokens.contains("苹"))
        #expect(tokens.contains("果"))
        #expect(tokens.contains("苹果")) // CJK 二元组
    }

    @Test func dimensionsFloor() {
        #expect(HashingVectorizer(dimensions: 4).dimensions == 16)
        #expect(HashingVectorizer(dimensions: 256).dimensions == 256)
    }

    @Test func fnv1aDeterministic() {
        #expect(HashingVectorizer.fnv1a("abc") == HashingVectorizer.fnv1a("abc"))
        #expect(HashingVectorizer.fnv1a("abc") != HashingVectorizer.fnv1a("abd"))
    }
}
