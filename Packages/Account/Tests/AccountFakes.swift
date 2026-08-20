@testable import Account
import Foundation
import Testing

// MARK: - 测试 Fakes

/// 可变的 fake iCloud 探测
final class FakeUbiquityProbe: UbiquityProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _containerURL: URL?
    private var _hasICloudAccount: Bool

    var containerURL: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _containerURL
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _containerURL = newValue
        }
    }

    var hasICloudAccount: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _hasICloudAccount
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _hasICloudAccount = newValue
        }
    }

    init(containerURL: URL? = nil, hasICloudAccount: Bool = true) {
        _containerURL = containerURL
        _hasICloudAccount = hasICloudAccount
    }

    func probe(containerIdentifier _: String) -> ICloudProbe {
        ICloudProbe(containerURL: containerURL, hasICloudAccount: hasICloudAccount)
    }
}

/// 内存 KVS（加锁线程安全，对齐生产实现的非隔离协议面）
final class FakeKVS: UbiquitousKeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]
    private var _syncCalls = 0
    private var _succeeds = true

    var syncCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _syncCalls
    }

    init() {}

    func setSuccess(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _succeeds = value
    }

    func set(_ value: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        data[key] = value
    }

    func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data[key]
    }

    @discardableResult
    func synchronize() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _syncCalls += 1
        return _succeeds
    }
}

/// 内存凭证库（加锁线程安全）
final class InMemoryCredentialStore: AppleCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: StoredAppleAccount?
    private var _loadCalls = 0

    var loadCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _loadCalls
    }

    init() {}

    func load() throws -> StoredAppleAccount? {
        lock.lock()
        defer { lock.unlock() }
        _loadCalls += 1
        return _stored
    }

    func save(_ account: StoredAppleAccount) throws {
        lock.lock()
        defer { lock.unlock() }
        _stored = account
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        _stored = nil
    }
}

/// fake 登录流程（默认立即回调，可切换延迟回调）
@MainActor
final class FakeAppleSigning: AppleSigning {
    enum DeliverMode {
        case immediate
        case delayed
    }

    var nextResult: Result<AppleSignInOutcome, Error>
    var nextCredentialState: AppleCredentialState
    var deliverMode: DeliverMode = .immediate
    var signInCalls = 0
    var lastExistingUserID: String?

    init(
        nextResult: Result<AppleSignInOutcome, Error> = .success(
            AppleSignInOutcome(userID: "user-test-001", email: "test@example.com", displayName: "Test User")
        ),
        nextCredentialState: AppleCredentialState = .authorized
    ) {
        self.nextResult = nextResult
        self.nextCredentialState = nextCredentialState
    }

    func signIn(existingUserID: String?, onResult: @escaping @MainActor (Result<AppleSignInOutcome, Error>) -> Void) {
        signInCalls += 1
        lastExistingUserID = existingUserID
        switch deliverMode {
        case .immediate:
            onResult(nextResult)
        case .delayed:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                onResult(nextResult)
            }
        }
    }

    func cancel() {}

    func credentialState(forUserID _: String) async -> AppleCredentialState {
        nextCredentialState
    }
}

/// 线程安全计数器（冲突回调捕获计数用）
final class ConflictCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _total = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _total
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _total == 0
    }

    func bump() {
        lock.lock()
        defer { lock.unlock() }
        _total += 1
    }
}

// MARK: - AccountService 测试夹具

@MainActor
final class AccountServiceFixture {
    let tempDir: URL
    let icloudContainer: URL
    let probe: FakeUbiquityProbe
    let credentialStore: InMemoryCredentialStore
    let signer: FakeAppleSigning
    let service: AccountService

    init(icloudAvailable: Bool = true, hasICloudAccount: Bool = true, signer: FakeAppleSigning? = nil) throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("account-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        icloudContainer = tempDir.appendingPathComponent("iCloudContainer", isDirectory: true)
        try FileManager.default.createDirectory(at: icloudContainer, withIntermediateDirectories: true)

        probe = FakeUbiquityProbe(containerURL: icloudAvailable ? icloudContainer : nil, hasICloudAccount: hasICloudAccount)
        credentialStore = InMemoryCredentialStore()
        let s = signer ?? FakeAppleSigning()
        self.signer = s
        let rootProvider = WorkspaceRootProvider(
            localRoot: tempDir.appendingPathComponent("LocalRoot", isDirectory: true),
            probe: probe
        )
        service = AccountService(
            rootProvider: rootProvider,
            probe: probe,
            credentialStore: credentialStore,
            signingFactory: { s },
            settingsURL: tempDir.appendingPathComponent("account.json")
        )
    }

    /// 构造共享同一 settings/探测/凭证库的服务实例（模拟 App 重启）
    func makeService(credentialStore: (any AppleCredentialStore)? = nil, signer: (any AppleSigning)? = nil) -> AccountService {
        let rootProvider = WorkspaceRootProvider(
            localRoot: tempDir.appendingPathComponent("LocalRoot", isDirectory: true),
            probe: probe
        )
        return AccountService(
            rootProvider: rootProvider,
            probe: probe,
            credentialStore: credentialStore ?? self.credentialStore,
            signingFactory: { signer ?? self.signer },
            settingsURL: tempDir.appendingPathComponent("account.json")
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
    }
}
