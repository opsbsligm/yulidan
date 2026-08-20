@testable import Account
import Foundation
import Testing

/// SSO 封装的纯逻辑面：nonce / 错误归类（UI 流程面为集成测试）
struct AppleSignInServiceTests {
    @Test func nonceIs64HexCharsAndUnique() {
        let a = RealAppleSignInService.makeNonce()
        let b = RealAppleSignInService.makeNonce()
        #expect(a.count == 64)
        #expect(b.count == 64)
        #expect(a != b)
        let allHex = a.allSatisfy(\.isHexDigit)
        #expect(allHex)
    }

    @Test func classifyUserCancelled() {
        let err = NSError(domain: NSCocoaErrorDomain, code: CocoaError.userCancelled.rawValue, userInfo: nil)
        let classified = RealAppleSignInService.classify(err)
        #expect((classified as? AppleSignInError) == .userCancelled)
    }

    @Test func classifyGenericErrorKeepsSystemDescription() {
        let err = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let classified = RealAppleSignInService.classify(err)
        guard let matched = classified as? AppleSignInError, case let .authorizationFailed(detail) = matched else {
            Issue.record("期望 authorizationFailed，实际 \(classified)")
            return
        }
        #expect(detail == "boom")
    }

    @Test func errorDescriptions() {
        #expect(AccountService.describe(AppleSignInError.userCancelled) == "已取消登录")
        #expect(AccountService.describe(AppleSignInError.alreadyInProgress) == "已有登录流程在进行中")
        #expect(AccountService.describe(AppleSignInError.noPresentationAnchor) == "无可用呈现窗口")
        #expect(AccountService.describe(AppleSignInError.authorizationFailed("x")) == "登录失败：x")
    }
}
