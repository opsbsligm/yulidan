import Foundation

/// 类型安全的依赖注入容器 (Actor 隔离)
public actor ServiceContainer {
    public enum ServiceScope: Sendable, Codable {
        case single
        case transient
    }

    private var instances: [ObjectIdentifier: Any] = [:]
    private var factories: [ObjectIdentifier: AnyObject] = [:]
    private var scopes: [ObjectIdentifier: ServiceScope] = [:]

    public init() {}

    public func register<T: Sendable>(_ instance: T, for type: T.Type, scope: ServiceScope = .single) {
        let oid = ObjectIdentifier(type)
        instances[oid] = instance
        scopes[oid] = scope
    }

    public func register<T: Sendable>(
        scope: ServiceScope = .single,
        factory: @escaping @Sendable () async throws -> T
    ) {
        let oid = ObjectIdentifier(T.self)
        factories[oid] = FactoryBox(factory)
        scopes[oid] = scope
    }

    public func resolve<T: Sendable>(_ type: T.Type) async throws -> T {
        let oid = ObjectIdentifier(type)

        if let cached = instances[oid] as? T, scopes[oid] == .single {
            return cached
        }

        // 类型化工厂盒：注册/解析类型不一致时抛错而非强转崩溃
        guard let box = factories[oid] as? FactoryBox<T> else {
            if factories[oid] != nil {
                throw ContainerError.typeMismatch(
                    expected: String(describing: type),
                    actual: "已注册的其他类型"
                )
            }
            throw ContainerError.notFound(String(describing: type))
        }
        let instance: T = try await box.makeInstance()

        if scopes[oid] != .transient {
            instances[oid] = instance
        }

        return instance
    }

    public func tryResolve<T: Sendable>(_ type: T.Type) async -> T? {
        do { return try await resolve(type) } catch { return nil }
    }

    public func isRegistered(_ type: (some Sendable).Type) -> Bool {
        let oid = ObjectIdentifier(type)
        return instances[oid] != nil || factories[oid] != nil
    }

    public func clear(_ type: (some Sendable).Type) {
        instances.removeValue(forKey: ObjectIdentifier(type))
    }

    public func reset() {
        instances.removeAll()
        scopes.removeAll()
    }
}

public enum ContainerError: Error, Sendable, CustomStringConvertible {
    case notFound(String)
    case typeMismatch(expected: String, actual: String)
    case circularDependency([String])
    case registrationFailed(reason: String)

    public var description: String {
        switch self {
        case let .notFound(t): "Service not found: \(t)"
        case let .typeMismatch(e, a): "Type mismatch: \(e) vs \(a)"
        case let .circularDependency(c): "Circular dependency: \(c)"
        case let .registrationFailed(r): "Registration failed: \(r)"
        }
    }
}

/// 类型化工厂盒：以泛型方式保存具体类型 T 的工厂，
/// 避免 resolve 时 `() async throws -> Any` 强转为 `-> T`（SwiftLint force_cast）。
private final class FactoryBox<T: Sendable>: Sendable {
    private let make: @Sendable () async throws -> T

    init(_ make: @escaping @Sendable () async throws -> T) {
        self.make = make
    }

    func makeInstance() async throws -> T {
        try await make()
    }
}
