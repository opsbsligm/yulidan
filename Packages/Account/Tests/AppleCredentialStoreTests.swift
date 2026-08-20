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
