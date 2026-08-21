import Foundation

/// 单条元数据的同步载荷（值 + 版本信息）
public struct SyncedValue: Codable, Equatable, Sendable {
    public let value: Data
    public let updatedAt: Date
    public let deviceId: String

    public init(value: Data, updatedAt: Date, deviceId: String) {
        self.value = value
        self.updatedAt = updatedAt
        self.deviceId = deviceId
    }
}

/// KVS 外部变更原因（与 NSUbiquitousKeyValueStore.ChangeReason 原始值对应）
public enum KVSChangeReason: Equatable, Sendable {
    case serverChange
    case initialSyncChange
    case quotaViolationChange
    case accountChange
    case unknown
}

/// 冲突记录（需用户裁决保留哪一侧）
public struct SyncConflict: Equatable, Sendable {
    public let key: String
    public let local: SyncedValue
    public let remote: SyncedValue

    public init(key: String, local: SyncedValue, remote: SyncedValue) {
        self.key = key
        self.local = local
        self.remote = remote
    }
}

/// 离线优先元数据同步服务（KVS 层）。
/// 语义：
/// - publish 立即写入 KVS（KVS 本身离线暂存、联网补同步），同时记录本机写入基线
/// - 外部变更到达时，若远端值 ≠ 本机未确认基线且来自其他设备 → 冲突，交 onConflict 回调裁决
/// - 无回调时保留本地值（离线优先原则），等待下一轮
/// - accountChange（iCloud 账号切换/退出）→ 清空基线，由上层降级
public actor MetadataSyncService {
    private let store: any UbiquitousKeyValueStoring
    private let stagingDir: URL
    private let deviceId: String
    private var managedKeys: Set<String> = []
    private var pending: [String: SyncedValue] = [:]
    private var remoteBaseline: [String: SyncedValue] = [:]

    /// 冲突回调：返回胜者载荷（UI 弹窗由用户选择）。nil = 保留本地
    public var onConflict: (@Sendable (SyncConflict) async -> SyncedValue)?

    public init(store: any UbiquitousKeyValueStoring, stagingDir: URL, deviceId: String) {
        self.store = store
        self.stagingDir = stagingDir
        self.deviceId = deviceId
    }

    // MARK: - 生命周期

    public func configure(managedKeys: [String]) {
        self.managedKeys = Set(managedKeys)
    }

    /// 设置冲突裁决回调（actor 属性外部不可直接赋值，提供显式入口）
    public func setOnConflict(_ handler: (@Sendable (SyncConflict) async -> SyncedValue)?) {
        onConflict = handler
    }

    /// 从磁盘恢复离线队列（App 启动时调用）
    public func loadStaging() {
        guard let data = try? Data(contentsOf: stagingFileURL) else { return }
        pending = (try? JSONDecoder().decode([String: SyncedValue].self, from: data)) ?? [:]
    }

    // MARK: - 读写

    /// 生效值（本地优先：pending > 远端基线 > 远端实时读）
    public func value(forKey key: String) -> Data? {
        if let p = pending[key] {
            return p.value
        }
        if let b = remoteBaseline[key] {
            return b.value
        }
        return store.data(forKey: key).flatMap { Self.decode($0)?.value }
    }

    /// 离线优先发布：立即写 KVS + 记录基线；远端已有异源值时走冲突裁决
    public func publish(key: String, value: Data) async {
        managedKeys.insert(key)
        let entry = SyncedValue(value: value, updatedAt: .now, deviceId: deviceId)
        pending[key] = entry
        await push(key)
    }

    /// 拉取远端变更（外部变更通知 / 启动时调用）
    public func pull() async {
        for key in managedKeys {
            guard let remote = readRemote(key) else { continue }
            if let local = pending[key] {
                await resolveConflict(key: key, local: local, remote: remote)
            } else {
                remoteBaseline[key] = remote
            }
        }
    }

    /// 处理外部 KVS 变更（生产由 didChangeExternally 通知胶合层调用）
    /// - Returns: true = iCloud 账号变更，调用方应执行降级
    @discardableResult
    public func handleExternalChange(reason: KVSChangeReason) async -> Bool {
        switch reason {
        case .accountChange:
            pending = [:]
            remoteBaseline = [:]
            persistStaging()
            return true
        default:
            await pull()
            return false
        }
    }

    @discardableResult
    public func isOnline() -> Bool {
        store.synchronize()
    }

    public var pendingKeys: [String] {
        pending.keys.sorted()
    }

    // MARK: - 私有

    private func push(_ key: String) async {
        guard let local = pending[key] else { return }
        if let remote = readRemote(key) {
            if remote == local {
                // 已传播（同值）
                pending[key] = nil
                remoteBaseline[key] = remote
            } else if remote.deviceId == deviceId {
                // 同设备写入（如另一进程）：新者胜
                let winner = remote.updatedAt > local.updatedAt ? remote : local
                store.set(Self.encode(winner), forKey: key)
                remoteBaseline[key] = winner
                pending[key] = nil
            } else {
                // 异设备变更 → 冲突
                await resolveConflict(key: key, local: local, remote: remote)
            }
        } else {
            store.set(Self.encode(local), forKey: key)
            remoteBaseline[key] = local
            pending[key] = nil
        }
        persistStaging()
        _ = store.synchronize()
    }

    private func resolveConflict(key: String, local: SyncedValue, remote: SyncedValue) async {
        remoteBaseline[key] = remote
        guard let onConflict else {
            // 无回调：保留本地（离线优先），pending 留在队列等待下一轮
            return
        }
        let winner = await onConflict(SyncConflict(key: key, local: local, remote: remote))
        store.set(Self.encode(winner), forKey: key)
        remoteBaseline[key] = winner
        pending[key] = nil
        persistStaging()
    }

    private func readRemote(_ key: String) -> SyncedValue? {
        store.data(forKey: key).flatMap(Self.decode)
    }

    private static func decode(_ data: Data) -> SyncedValue? {
        try? JSONDecoder().decode(SyncedValue.self, from: data)
    }

    private static func encode(_ value: SyncedValue) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private var stagingFileURL: URL {
        stagingDir.appendingPathComponent("pending.json")
    }

    private func persistStaging() {
        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(pending)
            try data.write(to: stagingFileURL, options: .atomic)
        } catch {
            // 队列持久化失败仅影响离线恢复能力，不中断主流程
        }
    }
}
