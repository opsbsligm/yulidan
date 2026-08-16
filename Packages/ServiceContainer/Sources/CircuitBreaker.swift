import Foundation

public actor CircuitBreaker {
    public enum State: Sendable {
        case closed
        case open
        case halfOpen
    }
    
    public var state: State = .closed
    public var failureCount: Int = 0
    public var successCount: Int = 0
    
    private let failureThreshold: Int
    private let successThreshold: Int
    private let resetTimeout: TimeInterval
    private var openUntil: Date?
    
    public init(
        failureThreshold: Int = 5,
        successThreshold: Int = 3,
        resetTimeout: TimeInterval = 30
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.resetTimeout = resetTimeout
        self.openUntil = nil
    }
    
    public func call<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        switch state {
        case .closed:
            do {
                failureCount = 0
                return try await operation()
            } catch {
                failureCount += 1
                if failureCount >= failureThreshold {
                    open()
                }
                throw error
            }
            
        case .open:
            if let openUntil, Date() >= openUntil {
                state = .halfOpen
                successCount = 0
                return try await call(operation)
            }
            throw CircuitBreakerError.open
            
        case .halfOpen:
            do {
                let result = try await operation()
                successCount += 1
                if successCount >= successThreshold {
                    state = .closed
                    failureCount = 0
                    successCount = 0
                }
                return result
            } catch {
                open()
                throw error
            }
        }
    }
    
    private func open() {
        state = .open
        openUntil = Date().addingTimeInterval(resetTimeout)
    }
    
    public func reset() {
        state = .closed
        failureCount = 0
        successCount = 0
        openUntil = nil
    }
}

public enum CircuitBreakerError: Error, Sendable, CustomStringConvertible {
    case open
    case timeout
    case maxAttemptsExceeded
    
    public var description: String {
        switch self {
        case .open: return "Circuit breaker is open"
        case .timeout: return "Circuit breaker timeout"
        case .maxAttemptsExceeded: return "Max attempts exceeded"
        }
    }
}
