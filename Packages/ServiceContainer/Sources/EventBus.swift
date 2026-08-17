import Foundation

public protocol EventType: Sendable, Codable {}

public struct EventEnvelope: Sendable, Codable {
    public let eventTypeName: String
    public let payload: AnyCodable
    public let source: String?
    public let timestamp: Date
    public init(eventTypeName: String, payload: AnyCodable, source: String? = nil) {
        self.eventTypeName = eventTypeName
        self.payload = payload
        self.source = source
        timestamp = Date()
    }
}

public typealias EventHandler = @Sendable (AnyCodable) async -> Void
public typealias WaterfallHandler = @Sendable (AnyCodable, @Sendable () async -> AnyCodable?) async -> AnyCodable?

public actor EventBus {
    private var emitHandlers: [String: [EventHandler]] = [:]
    private var waterfallHandlers: [String: [WaterfallHandler]] = [:]
    private var parallelHandlers: [String: [EventHandler]] = [:]
    private var serialHandlers: [String: [EventHandler]] = [:]

    public init() {}

    public func onEmit(eventType: String, handler: @escaping EventHandler) {
        emitHandlers[eventType, default: []].append(handler)
    }

    public func onWaterfall(eventType: String, handler: @escaping WaterfallHandler) {
        waterfallHandlers[eventType, default: []].append(handler)
    }

    public func onParallel(eventType: String, handler: @escaping EventHandler) {
        parallelHandlers[eventType, default: []].append(handler)
    }

    public func onSerial(eventType: String, handler: @escaping EventHandler) {
        serialHandlers[eventType, default: []].append(handler)
    }

    public func emit(payload: AnyCodable, eventType: String) {
        let handlers = emitHandlers[eventType] ?? []
        for handler in handlers {
            Task { await handler(payload) }
        }
    }

    public func waterfall(payload: AnyCodable, eventType: String) async -> AnyCodable? {
        let handlers = waterfallHandlers[eventType] ?? []
        var result: AnyCodable? = payload
        for handler in handlers {
            let previous = result
            let next: @Sendable () async -> AnyCodable? = { previous }
            result = await handler(payload, next) ?? result
        }
        return result
    }

    public func parallel(payload: AnyCodable, eventType: String) async {
        let handlers = parallelHandlers[eventType] ?? []
        await withTaskGroup(of: Void.self) { group in
            for handler in handlers {
                group.addTask { await handler(payload) }
            }
            for await _ in group {}
        }
    }

    public func serial(payload: AnyCodable, eventType: String) async {
        let handlers = serialHandlers[eventType] ?? []
        for handler in handlers {
            await handler(payload)
        }
    }

    public func clear(eventType: String) {
        emitHandlers.removeValue(forKey: eventType)
        waterfallHandlers.removeValue(forKey: eventType)
        parallelHandlers.removeValue(forKey: eventType)
        serialHandlers.removeValue(forKey: eventType)
    }

    public func clearAll() {
        emitHandlers.removeAll()
        waterfallHandlers.removeAll()
        parallelHandlers.removeAll()
        serialHandlers.removeAll()
    }
}
