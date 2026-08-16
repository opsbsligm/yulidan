import Foundation

/// 类型安全的依赖注入容器 (Actor 隔离)
public actor ServiceContainer {
    public enum ServiceScope: Sendable, Codable {
        case single
        case transient
    }
    
    private var instances: [ObjectIdentifier: Any] = [:]
    private var factories: [ObjectIdentifier: @Sendable () async throws -> Any] = [:]
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
        factories[oid] = { [factory] in try await factory() as Any }
        scopes[oid] = scope
    }
    
    public func resolve<T: Sendable>(_ type: T.Type) async throws -> T {
        let oid = ObjectIdentifier(type)
        
        if let cached = instances[oid] as? T, scopes[oid] == .single {
            return cached
        }
        
        guard let factoryRaw = factories[oid] else {
            throw ContainerError.notFound(String(describing: type))
        }
        
        let factory = factoryRaw as! @Sendable () async throws -> T
        let instance: T = try await factory()
        
        if scopes[oid] != .transient {
            instances[oid] = instance
        }
        
        return instance
    }
    
    public func tryResolve<T: Sendable>(_ type: T.Type) async -> T? {
        do { return try await resolve(type) } catch { return nil }
    }
    
    public func isRegistered<T: Sendable>(_ type: T.Type) -> Bool {
        let oid = ObjectIdentifier(type)
        return instances[oid] != nil || factories[oid] != nil
    }
    
    public func clear<T: Sendable>(_ type: T.Type) {
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
        case .notFound(let t): return "Service not found: \(t)"
        case .typeMismatch(let e, let a): return "Type mismatch: \(e) vs \(a)"
        case .circularDependency(let c): return "Circular dependency: \(c)"
        case .registrationFailed(let r): return "Registration failed: \(r)"
        }
    }
}
