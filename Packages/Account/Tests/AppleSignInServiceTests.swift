@testable import Account
import AuthenticationServices
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

    // MARK: outcome(from:) 覆盖限制（SDK 实证，铁律 1）

    // ASAuthorizationAppleIDCredential 全部属性 readonly 且 init/new 标 NS_UNAVAILABLE（ASAuthorizationAppleIDCredential.h L79-80），
    // 凭证仅能由真实 Sign in with Apple 流程产出 → 单测不可构造，该路径留待付费 Team + 实机 SSO 验收（P0 §1 走查项）。
    // outcome 映射本身 = 3 属性读取 + 姓名组件拼接（源码在案），classify/map/nonce 纯逻辑面覆盖如下。

    @Test func credentialStateMappingAllCases() {
        // SDK 实证（AuthenticationServices ObjC NS_ENUM）：状态与 credential 分离传参，
        // Swift 导入为无关联值枚举 → map 纯状态映射
        #expect(RealAppleSignInService.map(.authorized) == .authorized)
        #expect(RealAppleSignInService.map(.notFound) == .notFound)
        #expect(RealAppleSignInService.map(.revoked) == .revoked)
        #expect(RealAppleSignInService.map(.transferred) == .transferred)
    }

    @Test func classifyAS1000MissingEntitlementHonestMessage() {
        // AS 1000：ad-hoc 无 entitlement 的典型错误（官方未公开错误码表，社区共识成因，注释在案）
        let err = NSError(domain: "com.apple.AuthenticationServices.AuthorizationError", code: 1000, userInfo: nil)
        let classified = RealAppleSignInService.classify(err)
        guard case let .authorizationFailed(detail) = classified as? AppleSignInError else {
            Issue.record("期望 authorizationFailed，实际 \(classified)")
            return
        }
        #expect(detail.contains("Sign in with Apple"))
        #expect(detail.contains("付费"))
    }

    @Test func errorDescriptions() {
        #expect(AccountService.describe(AppleSignInError.userCancelled) == "已取消登录")
        #expect(AccountService.describe(AppleSignInError.alreadyInProgress) == "已有登录流程在进行中")
        #expect(AccountService.describe(AppleSignInError.noPresentationAnchor) == "无可用呈现窗口")
        #expect(AccountService.describe(AppleSignInError.authorizationFailed("x")) == "登录失败：x")
    }
}
