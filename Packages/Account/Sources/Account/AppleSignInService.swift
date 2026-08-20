import AppKit
import AuthenticationServices
import Foundation
import Security

// MARK: - 错误

public enum AppleSignInError: Error, Equatable, Sendable {
    /// 已有登录流程在进行中
    case alreadyInProgress
    /// 用户取消
    case userCancelled
    /// 授权失败（携带底层错误描述）
    case authorizationFailed(String)
    /// 无可用呈现窗口（anchor）
    case noPresentationAnchor
}

// MARK: - 结果模型（隔离 AuthenticationServices 类型与上层）

public struct AppleSignInOutcome: Equatable, Sendable {
    public let userID: String
    public let email: String?
    public let displayName: String?

    public init(userID: String, email: String?, displayName: String?) {
        self.userID = userID
        self.email = email
        self.displayName = displayName
    }
}

/// Apple ID 凭证状态（映射 ASAuthorizationAppleIDProvider.CredentialState）
public enum AppleCredentialState: Equatable, Sendable {
    case authorized
    case revoked
    case notFound
    case transferred
}

// MARK: - 登录抽象（生产 = AuthenticationServices，测试 = fake）

@MainActor
public protocol AppleSigning: AnyObject {
    /// 发起登录流程；回调投递于主线程
    func signIn(existingUserID: String?, onResult: @escaping @MainActor (Result<AppleSignInOutcome, Error>) -> Void)
    func cancel()
    /// 查询既有 userID 的凭证状态（App 启动重授权校验）
    func credentialState(forUserID: String) async -> AppleCredentialState
}

// MARK: - 生产实现（AuthenticationServices 原生）

/// Sign in with Apple 原生封装。
/// 关键取证（macOS 26.5 SDK / macOS 27 运行时，编译+运行时双重验证）：
/// - 请求必须经 `ASAuthorizationAppleIDProvider().createRequest()` 创建；
///   直接 `ASAuthorizationAppleIDRequest()` 不可用（父类 init 被标 NS_UNAVAILABLE，运行时调用 crash）
/// - macOS 呈现锚点为 `ASPresentationAnchor = NSWindow`（SDK 26.5 typedef 实测）；
///   macOS 不存在 `ASPresentationContext` / `presentationContextForAuthorization`
/// - `ASAuthorizationController` 与 delegate 协议标注 NS_SWIFT_UI_ACTOR → 本类整体 MainActor 隔离
@MainActor
public final class RealAppleSignInService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, AppleSigning {
    private var inFlight: ASAuthorizationController?
    private var pending: (@MainActor (Result<ASAuthorizationAppleIDCredential, Error>) -> Void)?

    override public init() {
        super.init()
    }

    // MARK: AppleSigning

    public func signIn(existingUserID: String?, onResult: @escaping @MainActor (Result<AppleSignInOutcome, Error>) -> Void) {
        guard inFlight == nil else {
            onResult(.failure(AppleSignInError.alreadyInProgress))
            return
        }
        guard NSApp.mainWindow != nil else {
            onResult(.failure(AppleSignInError.noPresentationAnchor))
            return
        }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [ASAuthorization.Scope.fullName, .email]
        request.nonce = Self.makeNonce()
        request.user = existingUserID

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        inFlight = controller
        pending = { [weak self] result in
            switch result {
            case let .success(credential):
                if let outcome = Self.outcome(from: credential) {
                    onResult(.success(outcome))
                } else {
                    onResult(.failure(AppleSignInError.authorizationFailed("凭证缺少 userID")))
                }
            case let .failure(error):
                onResult(.failure(Self.classify(error)))
            }
            self?.cleanup()
        }
        controller.performRequests()
    }

    public func cancel() {
        inFlight?.cancel()
        cleanup()
    }

    public func credentialState(forUserID: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: forUserID) { state, _ in
                continuation.resume(returning: Self.map(state))
            }
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    @objc(authorizationController:didCompleteWithAuthorization:)
    public func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        inFlight = nil
        let callback = pending
        pending = nil
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            callback?(.failure(AppleSignInError.authorizationFailed("意外的凭证类型")))
            return
        }
        callback?(.success(credential))
    }

    @objc(authorizationController:didCompleteWithError:)
    public func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        inFlight = nil
        let callback = pending
        pending = nil
        callback?(.failure(error))
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    @objc(presentationAnchorForAuthorizationController:)
    public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.mainWindow ?? NSWindow()
    }

    // MARK: - 辅助

    private func cleanup() {
        inFlight = nil
        pending = nil
    }

    /// 32 字节安全随机 nonce（64 位 hex）
    public nonisolated static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 凭证 → 结果模型映射（userID 缺失视为无效）
    nonisolated static func outcome(from credential: ASAuthorizationAppleIDCredential) -> AppleSignInOutcome? {
        // 取证：credential.user 导入为非 Optional String（空串视为无效）
        guard !credential.user.isEmpty else { return nil }
        let userID = credential.user
        let name = credential.fullName
        let displayName = [name?.givenName, name?.familyName]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return AppleSignInOutcome(
            userID: userID,
            email: credential.email,
            displayName: displayName.isEmpty ? nil : displayName
        )
    }

    /// 错误归类：用户取消归一为 .userCancelled，其余保留系统描述
    nonisolated static func classify(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.code == CocoaError.userCancelled.rawValue {
            return AppleSignInError.userCancelled
        }
        return AppleSignInError.authorizationFailed(nsError.localizedDescription)
    }

    nonisolated static func map(_ state: ASAuthorizationAppleIDProvider.CredentialState) -> AppleCredentialState {
        switch state {
        case .authorized: return .authorized
        case .revoked: return .revoked
        case .notFound: return .notFound
        case .transferred: return .transferred
        @unknown default: return .notFound
        }
    }
}
