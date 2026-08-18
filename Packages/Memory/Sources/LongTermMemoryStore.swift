import Foundation

// MARK: - 长期记忆持久存储

/// 长期记忆存储（actor 隔离；内存索引 + JSON 原子持久化，与 RAG 同一持久化风格）
public actor LongTermMemoryStore {
    private var items: [String: MemoryItem] = [:]
    private let fileURL: URL?
    public private(set) var revision: Int = 0

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL {
            Self.load(items: &items, revision: &revision, from: fileURL)
        }
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".harness")
            .appendingPathComponent("memory")
            .appendingPathComponent("longterm.json")
    }

    public func upsert(_ item: MemoryItem) {
        items[item.id] = item
        revision += 1
    }

    public func byID(_ id: String) -> MemoryItem? {
        items[id]
    }

    public func remove(_ id: String) -> Bool {
        if items.removeValue(forKey: id) != nil {
            revision += 1
            return true
        }
        return false
    }

    public func all(activeOnly: Bool = true) -> [MemoryItem] {
        let list = items.values.filter { activeOnly ? $0.status == .active : true }
        return list.sorted { $0.significance > $1.significance || ($0.significance == $1.significance && $0.topic < $1.topic) }
    }

    /// 同主题的记忆（状态不限，含被取代历史）
    public func byTopic(_ topic: String) -> [MemoryItem] {
        items.values
            .filter { $0.topic == topic }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func count(activeOnly: Bool = true) -> Int {
        activeOnly ? items.values.count(where: { $0.status == .active }) : items.count
    }

    public func clear() {
        items.removeAll()
        revision += 1
    }

    // MARK: 持久化

    struct Persisted: Codable {
        let version: Int
        let revision: Int
        let items: [String: MemoryItem]
    }

    static func load(items: inout [String: MemoryItem], revision: inout Int, from url: URL) {
        guard
            let data = try? Data(contentsOf: url),
            let persisted = try? JSONDecoder().decode(Persisted.self, from: data)
        else {
            return
        }
        items = persisted.items
        revision = persisted.revision
    }

    public func save() {
        guard let fileURL else { return }
        let payload = Persisted(version: 1, revision: revision, items: items)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
