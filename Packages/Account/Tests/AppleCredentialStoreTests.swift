@testable import Account
import Foundation
import Testing

/// Keychain 凭证库：真实往返（唯一 service 名隔离，测后清理）
struct AppleCredentialStoreTests {
    @Test func keychainRoundtripUpdateAndDelete() throws {
        let store = KeychainAppleCredentialStore(service: "com.harness.accounttests.\(UUID().uuidString)")
        defer { try? store.delete() }

        #expect(try store.load() == nil)

        let account = StoredAppleAccount(userID: "u1", email: "e@x.com", displayName: "E X", signedInAt: .now)
        try store.save(account)
        #expect(try store.load() == account)

        // 覆盖写（update 路径）
        let account2 = StoredAppleAccount(userID: "u2", email: nil, displayName: nil, signedInAt: .now)
        try store.save(account2)
        #expect(try store.load() == account2)

        try store.delete()
        #expect(try store.load() == nil)
        // 幂等删除
        try store.delete()
    }
}

// MARK: - 失败分支（SecItemAPI 注入缝；status 语义以 Security 官方文档为准）

/// 可配置 status 的 fake（不触碰真实 Keychain）
struct FakeSecItemAPI: SecItemAPI, @unchecked Sendable {
    var copy: (OSStatus, AnyObject?) = (errSecSuccess, nil)
    var add: OSStatus = errSecSuccess
    var update: OSStatus = errSecSuccess
    var delete: OSStatus = errSecSuccess

    func copyMatching(_: [String: Any]) -> (status: OSStatus, result: AnyObject?) {
        copy
    }

    func add(_: [String: Any]) -> OSStatus {
        add
    }

    func update(_: [String: Any], _: [String: Any]) -> OSStatus {
        update
    }

    func delete(_: [String: Any]) -> OSStatus {
        delete
    }
}

@Suite("Keychain 凭证库失败分支（注入缝）")
struct KeychainAppleCredentialStoreFailureTests {
    private func expectAppleError(_ body: () throws -> Void, _ expected: AppleCredentialError) {
        do {
            try body()
            Issue.record("应抛 AppleCredentialError，实际成功")
        } catch let e as AppleCredentialError {
            #expect(e == expected)
        } catch {
            Issue.record("意外错误类型: \(error)")
        }
    }

    @Test("load：非 success/notFound status → keychainFailed(status)")
    func loadKeychainFailure() {
        var fake = FakeSecItemAPI()
        fake.copy = (errSecInteractionNotAllowed, nil)
        let store = KeychainAppleCredentialStore(service: "fake", api: fake)
        expectAppleError({ _ = try store.load() }, .keychainFailed(errSecInteractionNotAllowed))
    }

    @Test("load：success 但数据损坏 → encodingFailed")
    func loadCorruptData() {
        var fake = FakeSecItemAPI()
        fake.copy = (errSecSuccess, Data("not-json".utf8) as AnyObject)
        let store = KeychainAppleCredentialStore(service: "fake", api: fake)
        expectAppleError({ _ = try store.load() }, .encodingFailed)
    }

    @Test("save：duplicate → update 失败 → keychainFailed(updateStatus)")
    func saveUpdateFailure() {
        var fake = FakeSecItemAPI()
        fake.add = errSecDuplicateItem
        fake.update = errSecAuthFailed
        let store = KeychainAppleCredentialStore(service: "fake", api: fake)
        let account = StoredAppleAccount(userID: "u", email: nil, displayName: nil, signedInAt: .now)
        expectAppleError({ try store.save(account) }, .keychainFailed(errSecAuthFailed))
    }

    @Test("save：非 success/duplicate status → keychainFailed(status)")
    func saveOtherFailure() {
        var fake = FakeSecItemAPI()
        fake.add = errSecInteractionNotAllowed
        let store = KeychainAppleCredentialStore(service: "fake", api: fake)
        let account = StoredAppleAccount(userID: "u", email: nil, displayName: nil, signedInAt: .now)
        expectAppleError({ try store.save(account) }, .keychainFailed(errSecInteractionNotAllowed))
    }

    @Test("save：duplicate → update 成功 = 覆盖写正常路径")
    func saveUpdateSuccess() throws {
        var fake = FakeSecItemAPI()
        fake.add = errSecDuplicateItem
        fake.update = errSecSuccess
        let store = KeychainAppleCredentialStore(service: "fake", api: fake)
        let account = StoredAppleAccount(userID: "u", email: nil, displayName: nil, signedInAt: .now)
        try store.save(account) // 不应抛错
    }
}
