import Foundation

// MARK: - 检索结果（含来源溯源）

/// 检索命中（重排序后）；携带完整来源溯源
public struct RetrievedChunk: Sendable, Identifiable {
    public var id: String {
        chunk.id
    }

    public let chunk: RAGChunk
    /// 文档来源（路径/标识）
    public let source: String
    /// 文档标题
    public let title: String
    /// 最终得分（0…1，余弦 × 重排加成）
    public let score: Float
    /// 召回余弦分（重排前）
    public let cosineScore: Float
    /// 命中词重叠数（重排依据之一）
    public let termHits: Int
    /// 元数据（过滤条件回显）
    public let metadata: [String: String]

    /// 溯源引用：「来源 · 第 N 块 · 字符区间」
    public var citation: String {
        "\(title)（\(source) · 块 \(chunk.index + 1) · 字符 \(chunk.charStart)-\(chunk.charEnd)）"
    }

    public init(chunk: RAGChunk, source: String, title: String, score: Float,
                cosineScore: Float, termHits: Int, metadata: [String: String]) {
        self.chunk = chunk
        self.source = source
        self.title = title
        self.score = score
        self.cosineScore = cosineScore
        self.termHits = termHits
        self.metadata = metadata
    }
}

/// 检索参数
public struct RetrievalOptions: Sendable {
    /// 召回候选数（重排前）
    public var recallK: Int
    /// 最终返回数
    public var topK: Int
    /// 元数据等值过滤（可空）
    public var filter: [String: String]?

    public init(recallK: Int = 20, topK: Int = 5, filter: [String: String]? = nil) {
        self.recallK = recallK
        self.topK = topK
        self.filter = filter
    }
}

// MARK: - 引擎

/// RAG 引擎：加载解析 → 切片 → 向量化 → 存储 → 召回 → 重排 → 溯源
///
/// 重排策略（零模型、可解释）：
/// 1. 召回：向量余弦 top recallK；
/// 2. 重排：final = cosine + 0.3 × termOverlap（查询词元在块中的命中比例），
///    弥补纯词袋向量对关键词短语的欠敏感；
/// 3. 截断 topK，附来源溯源。
public actor RAGEngine {
    private let store: VectorStore
    private let vectorizer: any TextVectorizer
    private let chunking: ChunkingOptions

    public init(store: VectorStore,
                vectorizer: any TextVectorizer = HashingVectorizer(),
                chunking: ChunkingOptions = .init()) {
        self.store = store
        self.vectorizer = vectorizer
        self.chunking = chunking
    }

    // MARK: 入库

    /// 从路径入库（加载解析 + 切片 + 向量化 + 存储）
    @discardableResult
    public func ingestPath(_ path: String, metadata: [String: String] = [:]) async throws -> Int {
        let doc = try DocumentLoader.load(path: path)
        var merged = doc.metadata
        for (k, v) in metadata where merged[k] == nil {
            merged[k] = v
        }
        return await ingest(doc, metadata: merged)
    }

    /// 从内存文本入库
    @discardableResult
    public func ingestText(_ text: String, source: String, title: String? = nil,
                           metadata: [String: String] = [:]) async -> Int {
        await ingest(DocumentLoader.loadText(text, source: source, title: title, metadata: metadata))
    }

    /// 入库一个文档；返回切片数（同 id 覆盖）
    @discardableResult
    public func ingest(_ doc: LoadedDocument, metadata: [String: String]? = nil) async -> Int {
        let chunks = Chunker.chunk(doc.text, documentID: doc.id, options: chunking)
        guard !chunks.isEmpty else {
            return 0
        }
        let merged = metadata ?? doc.metadata
        let stored: [StoredChunk] = chunks.map { chunk in
            StoredChunk(id: chunk.id,
                        documentID: doc.id,
                        index: chunk.index,
                        text: chunk.text,
                        charStart: chunk.charStart,
                        charEnd: chunk.charEnd,
                        source: doc.source,
                        title: doc.title,
                        metadata: merged,
                        vector: vectorizer.embed(chunk.text))
        }
        await store.upsert(stored)
        return chunks.count
    }

    /// 移除文档
    public func removeDocument(_ documentID: String) async {
        await store.removeDocument(documentID)
    }

    /// 清空
    public func clear() async {
        await store.clear()
    }

    // MARK: 检索

    /// 检索（召回 + 重排 + 过滤 + 溯源）
    public func retrieve(query: String, options: RetrievalOptions = .init()) async -> [RetrievedChunk] {
        let queryTokens = Set(HashingVectorizer.tokenize(query))
        guard !queryTokens.isEmpty else {
            return []
        }
        let queryVector = vectorizer.embed(query)
        let candidates = await store.search(queryVector: queryVector,
                                            topK: options.recallK,
                                            filter: options.filter)
        var ranked = candidates.map { chunk -> (chunk: StoredChunk, score: Float, termHits: Int) in
            let hits = HashingVectorizer.tokenize(chunk.text).filter { queryTokens.contains($0) }.count
            let overlap = min(1, Float(hits) / max(1, Float(queryTokens.count)))
            let cosine = VectorMath.cosine(queryVector, chunk.vector)
            let final = min(1, cosine + 0.3 * overlap)
            return (chunk, final, hits)
        }
        ranked.sort { $0.score > $1.score }
        return Array(ranked.prefix(options.topK)).map { item in
            RetrievedChunk(chunk: RAGChunk(id: item.chunk.id,
                                           documentID: item.chunk.documentID,
                                           index: item.chunk.index,
                                           text: item.chunk.text,
                                           charStart: item.chunk.charStart,
                                           charEnd: item.chunk.charEnd),
                           source: item.chunk.source,
                           title: item.chunk.title,
                           score: item.score,
                           cosineScore: VectorMath.cosine(queryVector, item.chunk.vector),
                           termHits: item.termHits,
                           metadata: item.chunk.metadata)
        }
    }

    // MARK: 状态

    public func stats() async -> (documents: Int, chunks: Int, revision: Int) {
        await (store.documentIDs().count, store.totalCount(), store.revision)
    }

    public func documentIDs() async -> [String] {
        await store.documentIDs()
    }

    public func count(documentID: String) async -> Int {
        await store.count(documentID: documentID)
    }

    /// 持久化落盘（store 带文件时生效）
    public func save() async {
        await store.save()
    }
}

// MARK: - 进程级共享实例

/// 进程级共享 RAG 引擎（默认库：~/.harness/rag/index.json）
public actor SharedRAGEngine {
    public static let shared = SharedRAGEngine()

    public static var defaultIndexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".harness")
            .appendingPathComponent("rag")
            .appendingPathComponent("index.json")
    }

    private var engine: RAGEngine?

    public func get() -> RAGEngine {
        if let engine {
            return engine
        }
        let engine = RAGEngine(store: VectorStore(fileURL: Self.defaultIndexURL))
        self.engine = engine
        return engine
    }

    /// 测试用：注入自定义库
    public func replace(_ engine: RAGEngine) {
        self.engine = engine
    }
}
