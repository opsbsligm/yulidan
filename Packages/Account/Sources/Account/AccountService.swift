import Combine
import Foundation

/// 账号与工作区服务（P0.1 事实源：Apple SSO + iCloud + 双模式状态机）。
/// @MainActor：UI 直接观察 @Published 状态；探测 / Keychain / 小文件 IO 均为亚毫秒同步操作。
@MainActor
public final class AccountService: ObservableObject {
    // MARK: - 可观察状态

    @Published public private(set) var state: WorkspaceState = .local
    @Published public private(set) var lastProbe: ICloudProbe?
    @Published public private(set) var lastError: String?
    @Published public private(set) var account: StoredAppleAccount?
    /// iCloud 当前是否在线（synchronize 结果；nil = 未同步）
    @Published public private(set) var isOnline: Bool?

    // MARK: - 依赖（全部可注入，便于单测）

    public let rootProvider: WorkspaceRootProvider
    private let probe: any UbiquityProbing
    private let credentialStore: any AppleCredentialStore
    private let signingFactory: @MainActor () -> any AppleSigning
    private let settingsURL: URL

    private var activeSigner: (any AppleSigning)?
    private var syncService: MetadataSyncService?
    private var kvsObserver: (any NSObjectProtocol)?

    /// iCloud 容器标识
    public var containerIdentifier: String {
        rootProvider.containerIdentifier
    }

    /// 设备 ID（持久化，用于同步冲突来源识别）
    public private(set) var deviceId: UUID = .init()

    /// 元数据键：账号模式意图
    public static let keyAccountMode = "harness.meta.accountMode"

    public init(
        rootProvider: WorkspaceRootProvider? = nil,
        probe: (any UbiquityProbing)? = nil,
        credentialStore: (any AppleCredentialStore)? = nil,
        signingFactory: (@MainActor () -> any AppleSigning)? = nil,
        settingsURL: URL? = nil
    ) {
        let rootProvider = rootProvider ?? WorkspaceRootProvider()
        self.rootProvider = rootProvider
        self.probe = probe ?? DefaultUbiquityProbe()
        self.credentialStore = credentialStore ?? KeychainAppleCredentialStore()
        self.signingFactory = signingFactory ?? { RealAppleSignInService() }
        if let settingsURL {
            self.settingsURL = settingsURL
        } else {
            self.settingsURL = rootProvider.localRoot.appendingPathComponent("account.json")
        }
    }

    // MARK: - 启动恢复

    /// App 启动时恢复持久化状态（幂等）。
    /// 规则：本地模式 → 直接本地；SSO+iCloud 模式 → 校验凭证状态 + 容器可用性，任一失败自动降级。
    public func restore() {
        let settings = Self.loadSettings(from: settingsURL)
        if let settings {
            deviceId = settings.deviceId
        }
        account = try? credentialStore.load()

        guard settings?.mode == .ssoIcloud else {
            state = .local
            return
        }
        // 持久化为 SSO+iCloud 但凭证缺失（钥匙串被重置等）→ 降级并提示重新登录
        guard let account else {
            degrade(reason: "Apple 凭证未找到（钥匙串可能被重置），请重新登录")
            persist(.local)
            return
        }
        let signer = signer()
        Task { [weak self] in
            await self?.finishRestore(account: account, signer: signer)
        }
    }

    private func finishRestore(account: StoredAppleAccount, signer: any AppleSigning) async {
        switch await signer.credentialState(forUserID: account.userID) {
        case .authorized:
            enterICloudIfPossible(account: account)
        case .revoked:
            forgetCredential()
            degrade(reason: "Apple ID 授权已被用户撤销")
        case .notFound, .transferred:
            forgetCredential()
            degrade(reason: "Apple ID 凭证不存在或已转移")
        }
    }

    // MARK: - 登录流程

    /// 发起 Sign in with Apple（系统 sheet）
    public func signInWithApple() {
        guard state != .ssoPending else { return }
        lastError = nil
        state = .ssoPending
        let signer = signer()
        signer.signIn(existingUserID: account?.userID) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleSignInResult(result)
            }
        }
    }

    private func handleSignInResult(_ result: Result<AppleSignInOutcome, Error>) {
        switch result {
        case let .success(outcome):
            let newAccount = StoredAppleAccount(
                userID: outcome.userID, email: outcome.email,
                displayName: outcome.displayName, signedInAt: .now
            )
            account = newAccount
            do {
                try credentialStore.save(newAccount)
            } catch {
                lastError = "登录成功，但凭证写入钥匙串失败：\(error)"
            }
            enterICloudIfPossible(account: newAccount)
        case let .failure(error):
            state = .local
            lastError = Self.describe(error)
        }
    }

    // MARK: - 模式切换

    /// 切回离线本地模式（设置面板入口）
    public func switchToLocalMode() {
        activeSigner?.cancel()
        deactivateSync()
        persist(.local)
        state = .local
    }

    /// 重新申请 iCloud（降级后从设置页重试；无需重新登录）
    public func retryICloud() {
        guard account != nil else {
            lastError = "请先使用 Apple ID 登录"
            return
        }
        lastError = nil
        state = .ssoPending
        let p = probe.probe(containerIdentifier: containerIdentifier)
        lastProbe = p
        guard p.isAvailable, let root = rootProvider.resolveICloud() else {
            let reason = Self.describe(p)
            state = .icloudDegradedLocal(reason: reason)
            lastError = reason
            return
        }
        _ = try? rootProvider.materialize(root)
        persist(.ssoIcloud)
        state = .icloudReady
        activateSync()
    }

    /// 退出 Apple ID（清凭证、回本地）
    public func signOut() {
        activeSigner?.cancel()
        forgetCredential()
        deactivateSync()
        persist(.local)
        state = .local
    }

    // MARK: - 工作区

    /// 当前工作区根（存储路由权威）
    public var currentWorkspace: WorkspaceRoot {
        if state.isICloudReady, let root = rootProvider.resolveICloud() {
            return root
        }
        return rootProvider.resolveLocal()
    }

    // MARK: - 私有：状态迁移

    private func signer() -> any AppleSigning {
        if let activeSigner {
            return activeSigner
        }
        let s = signingFactory()
        activeSigner = s
        return s
    }

    private func enterICloudIfPossible(account _: StoredAppleAccount) {
        let p = probe.probe(containerIdentifier: containerIdentifier)
        lastProbe = p
        guard p.isAvailable, let root = rootProvider.resolveICloud() else {
            // iCloud 权限拒绝 / 无账号 / 无 entitlement → 自动降级本地
            degrade(reason: Self.describe(p))
            persist(.local)
            return
        }
        _ = try? rootProvider.materialize(root)
        persist(.ssoIcloud)
        state = .icloudReady
        lastError = nil
        activateSync()
    }

    private func forgetCredential() {
        try? credentialStore.delete()
        account = nil
    }

    private func degrade(reason: String) {
        deactivateSync()
        state = .icloudDegradedLocal(reason: reason)
        lastError = reason
    }

    // MARK: - 私有：KVS 元数据同步

    private func activateSync() {
        guard syncService == nil, state.isICloudReady, let icloudRoot = rootProvider.resolveICloud() else { return }
        let sync = MetadataSyncService(
            store: DefaultUbiquitousKeyValueStore(),
            stagingDir: icloudRoot.url(for: WorkspaceLayout.syncStaging),
            deviceId: deviceId.uuidString
        )
        syncService = sync
        Task { [weak sync] in
            await sync?.configure(managedKeys: [Self.keyAccountMode])
            await sync?.loadStaging()
            await sync?.publish(key: Self.keyAccountMode, value: Data("ssoIcloud".utf8))
        }
        observeKVSEvents()
        refreshOnlineState()
    }

    private func deactivateSync() {
        syncService = nil
        if let observer = kvsObserver {
            NotificationCenter.default.removeObserver(observer)
            kvsObserver = nil
        }
        isOnline = nil
    }

    private func refreshOnlineState() {
        Task { [weak self] in
            guard let self, let sync = syncService else { return }
            isOnline = await sync.isOnline()
        }
    }

    private func observeKVSEvents() {
        guard kvsObserver == nil else { return }
        kvsObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            // 非隔离闭包内先提取 Sendable 值，避免 Notification 跨 actor 边界
            let raw = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            Task { @MainActor [weak self] in
                guard let self else { return }
                await handleKVSExternalChange(reason: Self.mapChangeReason(raw))
            }
        }
    }

    /// 外部 KVS 变更入口（生产由通知胶合层调用；单测直接驱动）
    /// - Returns: true = iCloud 账号变更，已自动降级
    @discardableResult
    public func handleKVSExternalChange(reason: KVSChangeReason) async -> Bool {
        guard let sync = syncService else { return false }
        let accountChanged = await sync.handleExternalChange(reason: reason)
        if accountChanged {
            degrade(reason: "iCloud 账号已变更，已回退本地模式")
            persist(.local)
            return true
        }
        isOnline = await sync.isOnline()
        return false
    }

    /// KVS 变更原因原始值 → 枚举（与 NSUbiquitousKeyValueStore.ChangeReason 声明顺序一致：0 server / 1 initialSync / 2 quota / 3 account）
    nonisolated static func mapChangeReason(_ raw: Int?) -> KVSChangeReason {
        switch raw {
        case 0: .serverChange
        case 1: .initialSyncChange
        case 2: .quotaViolationChange
        case 3: .accountChange
        default: .unknown
        }
    }

    // MARK: - 私有：持久化（本地 settings 文件，离线优先）

    private struct AccountSettings: Codable {
        var mode: AccountMode
        var deviceId: UUID
    }

    private func persist(_ mode: AccountMode) {
        let settings = AccountSettings(mode: mode, deviceId: deviceId)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: settingsURL, options: .atomic)
    }

    private static func loadSettings(from url: URL) -> AccountSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AccountSettings.self, from: data)
    }

    // MARK: - 私有：描述文案

    nonisolated static func describe(_ probe: ICloudProbe) -> String {
        switch probe.result {
        case .available: "iCloud 容器可用"
        case .noICloudAccount: "设备未登录 iCloud 账号"
        case .noEntitlement: "iCloud 容器不可用（需配置 Apple 开发者 entitlement / 描述文件）"
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case AppleSignInError.userCancelled: "已取消登录"
        case AppleSignInError.alreadyInProgress: "已有登录流程在进行中"
        case AppleSignInError.noPresentationAnchor: "无可用呈现窗口"
        case let AppleSignInError.authorizationFailed(detail): "登录失败：\(detail)"
        default: (error as NSError).localizedDescription
        }
    }
}
