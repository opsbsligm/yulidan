import Foundation
import Security

/// 凭证持久化错误
public enum AppleCredentialError: Error, Equatable, Sendable {
    case keychainFailed(OSStatus)
    case encodingFailed
}

/// Apple ID 凭证持久化抽象（生产 = Keychain，测试 = 内存 fake）
public protocol AppleCredentialStore: Sendable {
    func load() throws -> StoredAppleAccount?
    func save(_ account: StoredAppleAccount) throws
    func delete() throws
}

/// SecItem 操作注入缝（生产 = 系统 Keychain 直调；测试 = 失败分支 fake。
/// 与 UbiquitousKeyValueStoring 同一模式：协议化后纯逻辑可单测，默认参数保证生产行为零变化）
public protocol SecItemAPI: Sendable {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?)
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

/// 生产实现：Security 框架直调（status 语义以 Security 官方文档为准：errSecSuccess/errSecItemNotFound/errSecDuplicateItem）
public struct SystemSecItemAPI: SecItemAPI, Sendable {
    public init() {}
    public func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    public func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Keychain 实现（generic password，ThisDeviceOnly 不备份不迁移）
public struct KeychainAppleCredentialStore: AppleCredentialStore {
    private let service: String
    private let api: any SecItemAPI
    private static let account = "apple.sso.credential.v1"

    public init(service: String = "com.harness.app", api: (any SecItemAPI)? = nil) {
        self.service = service
        self.api = api ?? SystemSecItemAPI()
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func load() throws -> StoredAppleAccount? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = api.copyMatching(query)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppleCredentialError.keychainFailed(status)
        }
        do {
            return try JSONDecoder().decode(StoredAppleAccount.self, from: data)
        } catch {
            throw AppleCredentialError.encodingFailed
        }
    }

    public func save(_ account: StoredAppleAccount) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(account)
        } catch {
            throw AppleCredentialError.encodingFailed
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = api.add(addQuery)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = api.update(baseQuery, [kSecValueData as String: data])
            guard updateStatus == errSecSuccess else { throw AppleCredentialError.keychainFailed(updateStatus) }
        default:
            throw AppleCredentialError.keychainFailed(status)
        }
    }

    public func delete() throws {
        let status = api.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleCredentialError.keychainFailed(status)
        }
    }
}
