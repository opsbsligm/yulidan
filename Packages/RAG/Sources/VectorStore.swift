import Foundation

// MARK: - 向量存储

/// 存储条目（向量 + 溯源元数据）
public struct StoredChunk: Codable, Sendable, Identifiable {
    public let id: String
    public let documentID: String
    public let index: Int
    public let text: String
    public let charStart: Int
    public let charEnd: Int
    /// 文档来源（路径/标识）
    public let source: String
    /// 文档标题
    public let title: String
    /// 元数据（过滤用）
    public let metadata: [String: String]
    public let vector: [Float]

    public init(id: String, documentID: String, index: Int, text: String, charStart: Int, charEnd: Int,
                source: String, title: String, metadata: [String: String], vector: [Float]) {
        self.id = id
        self.documentID = documentID
        self.index = index
        self.text = text
        self.charStart = charStart
        self.charEnd = charEnd
        self.source = source
        self.title = title
        self.metadata = metadata
        self.vector = vector
    }
}

/// 向量存储（actor 隔离；内存索引 + JSON 持久化）
public actor VectorStore {
    /// 按文档分组的条目
    private var entries: [String: [StoredChunk]] = [:]
    /// 持久化文件（nil = 纯内存）
    private let fileURL: URL?
    /// 版本号（重建/清空递增，调试用）
    public private(set) var revision: Int = 0

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL {
            Self.load(entries: &entries, revision: &revision, from: fileURL)
        }
    }

    /// 写入一批切片（同 documentID 先清空旧条目，支持重复入库覆盖）
    public func upsert(_ chunks: [StoredChunk]) {
        guard !chunks.isEmpty else { return }
        let docID = chunks[0].documentID
        entries[docID] = chunks
        revision += 1
    }

    /// 移除某文档全部切片
    public func removeDocument(_ documentID: String) {
        if entries.removeValue(forKey: documentID) != nil {
            revision += 1
        }
    }

    /// 清空
    public func clear() {
        entries.removeAll()
        revision += 1
    }

    /// 全部文档 ID
    public func documentIDs() -> [String] {
        entries.keys.sorted()
    }

    /// 某文档的切片数
    public func count(documentID: String) -> Int {
        entries[documentID]?.count ?? 0
    }

    /// 元数据等值匹配的全部文档 ID（如 content_hash 去重查询）
    public func documentIDs(matchingMetadata key: String, value: String) -> [String] {
        entries.filter { entry in
            entry.value.contains { $0.metadata[key] == value }
        }
        .keys.sorted()
    }

    /// 指定来源的全部文档 ID（同源更新去重用）
    public func documentIDs(withSource source: String) -> [String] {
        entries.filter { entry in
            entry.value.contains { $0.source == source }
        }
        .keys.sorted()
    }

    /// 总切片数
    public func totalCount() -> Int {
        entries.values.reduce(0) { $0 + $1.count }
    }

    /// 向量检索：余弦 topK（filter 为元数据等值过滤，可空）
    public func search(queryVector: [Float], topK: Int, filter: [String: String]? = nil) -> [StoredChunk] {
        var scored: [(chunk: StoredChunk, score: Float)] = []
        for docChunks in entries.values {
            for chunk in docChunks {
                if let filter, !matches(chunk.metadata, filter) {
                    continue
                }
                let score = VectorMath.cosine(queryVector, chunk.vector)
                if score > 0 {
                    scored.append((chunk, score))
                }
            }
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK).map(\.chunk))
    }

    /// 快照（持久化/调试）
    public func snapshot() -> [StoredChunk] {
        entries.values.flatMap(\.self).sorted { $0.documentID < $1.documentID || $0.index < $1.index }
    }

    // MARK: 持久化

    private func matches(_ metadata: [String: String], _ filter: [String: String]) -> Bool {
        for (key, value) in filter where metadata[key] != value {
            return false
        }
        return true
    }

    struct Persisted: Codable {
        let version: Int
        let revision: Int
        let entries: [String: [StoredChunk]]
    }

    public static func load(entries: inout [String: [StoredChunk]], revision: inout Int, from url: URL) {
        guard
            let data = try? Data(contentsOf: url),
            let persisted = try? JSONDecoder().decode(Persisted.self, from: data)
        else {
            return
        }
        entries = persisted.entries
        revision = persisted.revision
    }

    /// 保存（原子写入；fileURL 为空时忽略）
    public func save() {
        guard let fileURL else { return }
        let payload = Persisted(version: 1, revision: revision, entries: entries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
