import Foundation
import os.log

public struct PluginConfiguration: Sendable, Codable {
    public var entries: [String: AnyCodable] = [:]
    public init() {}
    public init(entries: [String: AnyCodable]) {
        self.entries = entries
    }
}

public actor Cancellation {
    private var _isCancelled: Bool = false
    public var isCancelled: Bool {
        _isCancelled
    }

    public func cancel() {
        _isCancelled = true
    }
}

public struct Effect: Sendable {
    private let disposer: @Sendable () -> Void
    public init(_ disposer: @escaping @Sendable () -> Void) {
        self.disposer = disposer
    }

    public func dispose() {
        disposer()
    }
}

/// 插件上下文
public struct PluginContext: @unchecked Sendable {
    public let container: ServiceContainer
    public let eventBus: EventBus
    public let configuration: PluginConfiguration
    public let logger: Logger
    public let cancellation: Cancellation

    public init(
        container: ServiceContainer,
        eventBus: EventBus,
        configuration: PluginConfiguration,
        logger: Logger,
        cancellation: Cancellation
    ) {
        self.container = container
        self.eventBus = eventBus
        self.configuration = configuration
        self.logger = logger
        self.cancellation = cancellation
    }
}

public extension Logger {
    static func pluginLogger(pluginID: PluginID, category: String = "default") -> Logger {
        Logger(subsystem: "com.harness", category: "\(pluginID.rawValue).\(category)")
    }
}
