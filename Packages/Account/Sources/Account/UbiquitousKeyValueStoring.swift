import Foundation

/// NSUbiquitousKeyValueStore 数据面抽象（测试可注入 fake）
public protocol UbiquitousKeyValueStoring: Sendable {
    func set(_ value: Data, forKey key: String)
    func data(forKey key: String) -> Data?
    /// 尝试与服务器同步；离线返回 false（KVS 本地暂存，联网自动补同步）
    @discardableResult
    func synchronize() -> Bool
}

/// 默认实现：包装系统 NSUbiquitousKeyValueStore。
/// KVS API 为线程安全（Apple 文档：多线程可访问，变更内部串行化），故整体按共享引用处理。
public struct DefaultUbiquitousKeyValueStore: UbiquitousKeyValueStoring, @unchecked Sendable {
    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func set(_ value: Data, forKey key: String) {
        store.set(value, forKey: key)
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }
}
