import Foundation
import LLM
import ServiceContainer
import Session

actor ToolPipeline {
    private var preExecuteHandlers: [@Sendable (ToolCall) async -> Bool] = []
    private var postExecuteHandlers: [@Sendable (ToolResult) async -> Void] = []
    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    func addPreExecuteHandler(_ handler: @escaping @Sendable (ToolCall) async -> Bool) {
        preExecuteHandlers.append(handler)
    }

    func addPostExecuteHandler(_ handler: @escaping @Sendable (ToolResult) async -> Void) {
        postExecuteHandlers.append(handler)
    }

    func execute(_ call: ToolCall) async throws -> ToolResult {
        for handler in preExecuteHandlers {
            guard await handler(call) else {
                throw ToolError(name: "rejected", code: "PRE_EXECUTE_REJECTED", message: "Rejected")
            }
        }

        guard let tool = await registry.tool(named: call.name) else {
            throw ToolError(name: "notFound", code: "TOOL_NOT_FOUND", message: "Tool not found")
        }

        let result = try await tool.execute(call.arguments, context: ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:]))

        for handler in postExecuteHandlers {
            await handler(result)
        }

        return result
    }
}

public struct ToolCall: Sendable {
    public let id: String
    public let name: String
    public let arguments: [String: String]

    public init(id: String = UUID().uuidString, name: String, arguments: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}
