import CryptoKit
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

    /// 入库一个文档；返回切片数（同 id 覆盖）。
    /// 去重语义（避免同文件重复入库产生重复块）：
    /// - 来源（source）是知识库中文档的规范标识；同 source 再入库 → 覆盖旧版本，不产生重复切片；
    /// - 异 source 即使内容相同也各自保留（允许同一内容挂不同来源标签）；
    /// - 元数据写入 content_hash（SHA256）供溯源与外部去重查询。
    @discardableResult
    public func ingest(_ doc: LoadedDocument, metadata: [String: String]? = nil) async -> Int {
        let chunks = Chunker.chunk(doc.text, documentID: doc.id, options: chunking)
        guard !chunks.isEmpty else {
            return 0
        }
        let merged = metadata ?? doc.metadata
        var deduped = merged
        deduped["content_hash"] = Self.sha256Hex(doc.text)
        // 同来源旧版本（同文件重复 ingest / 文件内容更新）先移除再入库
        for oldID in await store.documentIDs(withSource: doc.source) where oldID != doc.id {
            await store.removeDocument(oldID)
        }
        let stored: [StoredChunk] = chunks.map { chunk in
            StoredChunk(id: chunk.id,
                        documentID: doc.id,
                        index: chunk.index,
                        text: chunk.text,
                        charStart: chunk.charStart,
                        charEnd: chunk.charEnd,
                        source: doc.source,
                        title: doc.title,
                        metadata: deduped,
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

    /// 正文内容 SHA256（去重键）
    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
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
        harnessHomeBase()
            .appendingPathComponent("rag")
            .appendingPathComponent("index.json")
    }

    /// 当前索引路径（P0.1.5：工作区根切换时经 resetIndexURL 重路由，双根严格隔离不迁移）
    private var indexURL: URL

    public init(indexURL: URL? = nil) {
        self.indexURL = indexURL ?? Self.defaultIndexURL
    }

    /// P0.1.5：工作区根切换（本地 ⇄ iCloud）后重路由索引路径；
    /// 丢弃既有引擎实例，下次 get() 在新路径上重建（严格隔离，不自动迁移数据）
    public func resetIndexURL(_ url: URL) {
        indexURL = url
        engine = nil
    }

    /// ~/.harness 基础目录（HARNESS_HOME 环境变量可覆盖，测试/隔离运行用）
    private static func harnessHomeBase() -> URL {
        if let envHome = ProcessInfo.processInfo.environment["HARNESS_HOME"], !envHome.isEmpty {
            return URL(fileURLWithPath: (envHome as NSString).expandingTildeInPath)
                .appendingPathComponent(".harness")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".harness")
    }

    private var engine: RAGEngine?

    public func get() -> RAGEngine {
        if let engine {
            return engine
        }
        let engine = RAGEngine(store: VectorStore(fileURL: indexURL))
        self.engine = engine
        return engine
    }

    /// 测试用：注入自定义库
    public func replace(_ engine: RAGEngine) {
        self.engine = engine
    }
}
