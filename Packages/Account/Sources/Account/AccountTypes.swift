import Foundation

// MARK: - 账号模式（用户意图，持久化）

/// 顶层账号 / 工作区模式
public enum AccountMode: String, Codable, CaseIterable, Sendable {
    /// 离线本地模式：数据仅存本地磁盘
    case local
    /// iCloud 同步模式（SSO 为可选叠加层，不影响同步；名称保留历史 wire 值）
    case ssoIcloud
}

// MARK: - iCloud 探测

/// iCloud 容器探测结果（判定为纯逻辑，可单测）
public struct ICloudProbe: Equatable, Sendable {
    /// iCloud 容器根（nil = 容器不可用）
    public let containerURL: URL?
    /// 当前设备是否登录 iCloud 账号（ubiquityIdentityToken 非 nil）
    public let hasICloudAccount: Bool

    public init(containerURL: URL?, hasICloudAccount: Bool) {
        self.containerURL = containerURL
        self.hasICloudAccount = hasICloudAccount
    }

    /// 容器是否可用
    public var isAvailable: Bool {
        containerURL != nil
    }

    /// 探测判定：
    /// - 容器可用 → available
    /// - 容器缺失 + 无 iCloud 账号 → noICloudAccount（需引导登录 iCloud）
    /// - 容器缺失 + 有账号 → noEntitlement（缺 entitlement/描述文件，或权限被拒）
    public var result: ICloudProbeResult {
        guard containerURL == nil else { return .available }
        return hasICloudAccount ? .noEntitlement : .noICloudAccount
    }
}

/// 探测判定结论
public enum ICloudProbeResult: Equatable, Sendable {
    case available
    case noICloudAccount
    case noEntitlement
}

// MARK: - 工作区状态机

/// 工作区状态（UI 与存储路由的唯一事实源）
public enum WorkspaceState: Equatable, Sendable {
    /// 离线本地模式（默认态）
    case local
    /// SSO 流程进行中
    case ssoPending
    /// iCloud 同步就绪（不要求 SSO 登录；SSO 身份为可选叠加）
    case icloudReady
    /// iCloud 不可用，已自动降级本地（保留原因供展示与重新申请）
    case icloudDegradedLocal(reason: String)

    /// 生效存储模式（状态机对存储路由具有唯一权威）
    public var mode: AccountMode {
        self == .icloudReady ? .ssoIcloud : .local
    }

    public var isICloudReady: Bool {
        self == .icloudReady
    }

    /// 降级原因（仅 icloudDegradedLocal 态有值）
    public var degradationReason: String? {
        if case let .icloudDegradedLocal(reason) = self {
            return reason
        }
        return nil
    }
}

// MARK: - 已存储 Apple 账号

/// Apple ID 凭证快照（持久化于 Keychain）
public struct StoredAppleAccount: Codable, Equatable, Sendable {
    /// Opaque 标识（用于重新授权与凭证状态查询）
    public let userID: String
    public let email: String?
    public let displayName: String?
    public let signedInAt: Date

    public init(userID: String, email: String?, displayName: String?, signedInAt: Date) {
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.signedInAt = signedInAt
    }
}
