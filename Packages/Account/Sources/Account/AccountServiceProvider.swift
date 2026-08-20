import Foundation
import ServiceContainer

/// 将 Account 服务注册进依赖注入容器（基于 ServiceContainer 扩展，不重构核心架构）
public struct AccountServiceProvider: ServiceProvider {
    public init() {}

    public func provide(to container: ServiceContainer) async throws {
        let service: AccountService = await MainActor.run { AccountService() }
        await container.register(service, for: AccountService.self)
    }
}
