import Foundation

public protocol Service: Sendable {
    static var serviceKey: String { get }
}

public protocol ServiceProvider: Sendable {
    func provide(to container: ServiceContainer) async throws
}
