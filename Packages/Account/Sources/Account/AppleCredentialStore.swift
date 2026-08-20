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

/// Keychain 实现（generic password，ThisDeviceOnly 不备份不迁移）
public struct KeychainAppleCredentialStore: AppleCredentialStore {
    private let service: String
    private static let account = "apple.sso.credential.v1"

    public init(service: String = "com.harness.app") {
        self.service = service
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
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
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
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw AppleCredentialError.keychainFailed(updateStatus) }
        default:
            throw AppleCredentialError.keychainFailed(status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleCredentialError.keychainFailed(status)
        }
    }
}
