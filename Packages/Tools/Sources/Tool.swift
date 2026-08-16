import Foundation
import ServiceContainer
import Session
import LLM

public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameterSchema: String { get }
    var schema: ToolSchema { get }
    func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult
}

public extension Tool {
    var schema: ToolSchema {
        ToolSchema(name: name, description: description, parameters: parameterSchema)
    }
}

public struct ToolRunContext: @unchecked Sendable {
    public let signal: CancellationToken
    public let sessionID: SessionID
    public let metadata: [String: String]
    
    public init(signal: CancellationToken, sessionID: SessionID, metadata: [String: String]) {
        self.signal = signal
        self.sessionID = sessionID
        self.metadata = metadata
    }
}

public struct ToolResult: Sendable {
    public let content: [LLM.ContentBlock]
    public let error: ToolError?
    public let meta: [String: String]?
    
    public init(content: [LLM.ContentBlock], error: ToolError? = nil, meta: [String: String]? = nil) {
        self.content = content
        self.error = error
        self.meta = meta
    }
}

public struct ToolError: Sendable, Error {
    public let name: String
    public let code: String
    public let message: String
    
    public init(name: String, code: String, message: String) {
        self.name = name
        self.code = code
        self.message = message
    }
}

public final class CancellationToken: @unchecked Sendable {
    private var _isCancelled: Bool = false
    public init() {}
    public var isCancelled: Bool { _isCancelled }
    public func cancel() { _isCancelled = true }
}
